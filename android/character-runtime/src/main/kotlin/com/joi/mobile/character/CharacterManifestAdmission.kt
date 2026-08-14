package com.joi.mobile.character

import com.joi.mobile.core.CharacterAssetV1
import com.joi.mobile.core.CharacterMotionV1
import com.joi.mobile.core.CharacterPackageLimits
import com.joi.mobile.core.CharacterPackageManifestV1
import com.joi.mobile.core.CharacterProvenanceV1
import com.joi.mobile.core.CharacterRendererKind

/**
 * Document-level admission of `manifest.json`: everything a platform can decide
 * before it has opened a single asset.
 *
 * Desktop Joi and Joi Mobile currently use the same `joi.character.v1` label for
 * two incompatible envelopes, so the first job here is classification by exact,
 * non-overlapping shape. A document matching both families, or neither, is
 * refused before decoding rather than resolved by preference — guessing between
 * two wire formats is how one silently becomes the other.
 *
 * Pinned by `Contracts/conformance/manifest-validation.json`, which the iOS
 * implementation runs against the same expectations.
 */
object CharacterManifestAdmission {

    sealed interface Admission {
        /** A mobile-canonical manifest, decoded. Asset verification is a later stage. */
        data class Canonical(val manifest: CharacterPackageManifestV1) : Admission

        /**
         * A desktop-legacy document whose document-level checks passed.
         *
         * Adaptation cannot finish here: the legacy envelope names a model but no
         * asset list, so the canonical manifest can only be built once the tree is
         * readable. This carries what the document alone established.
         */
        data class LegacyPending(
            val characterID: String,
            val displayName: String,
            val version: String,
            val renderer: CharacterRendererKind,
            val entryPath: String,
            val portraitPath: String?,
            val locale: String,
            val warnings: List<String>,
        ) : Admission
    }

    private val CANONICAL_REQUIRED = setOf(
        "schema", "packageID", "characterID", "version", "displayName",
        "renderer", "entryPath", "locales", "assets", "provenance",
    )
    private val CANONICAL_ALLOWED = CANONICAL_REQUIRED + setOf("portraitPath", "motions")

    /** The keys whose joint presence means "this is the mobile envelope". */
    private val CANONICAL_FAMILY = setOf("packageID", "characterID", "renderer", "entryPath", "assets", "provenance")
    private val CANONICAL_EXCLUSIVE = setOf("packageID", "characterID", "renderer", "entryPath", "assets")
    private val LEGACY_FAMILY = setOf("id", "identity", "appearance")
    private val LEGACY_ALLOWED = setOf(
        "schema", "id", "version", "locale", "locales", "identity", "appearance", "persona", "voice",
        "lorebook", "license", "knowledge", "capabilities", "creator", "source", "provenance",
        "security", "localizations", "extensions",
    )

    /**
     * Key fragments a character package may never carry, at any depth.
     *
     * A character is appearance, voice and persona. Memory, permissions, sync
     * state and credentials belong to the person using the app, and a package
     * that arrives carrying them is either a mistake or an attempt to import
     * somebody else's state as though it were art.
     */
    private val FORBIDDEN_FRAGMENTS = listOf(
        "memory", "messages", "affinity", "permission", "secret", "sync", "runtime", "token",
        "apikey", "api_key", "credential", "grant", "capability", "modelweight", "model_weight",
        "privatekey", "private_key",
    )

    private const val MAXIMUM_STRING_BYTES = 12_000
    private const val MAXIMUM_WALK_DEPTH = 32

    /**
     * A generic anti-blowup bound on an array anywhere in a package document. It
     * exists so a hostile document cannot make the forbidden-content walk
     * expensive; it says nothing about how many files a character may have.
     */
    private const val MAXIMUM_ARRAY_ELEMENTS = 300

    fun admit(documentBytes: ByteArray): Admission {
        val document = StrictJson.objectOf(documentBytes, CharacterPackageLimits.MAXIMUM_MANIFEST_BYTES)
        val members = document.members

        // The label is checked before classification, so a future schema version
        // is refused rather than guessed at.
        if ((members["schema"] as? JsonValue.Text)?.value != CharacterPackageManifestV1.SCHEMA) {
            throw invalidManifest()
        }

        val keys = members.keys
        val canonical = CANONICAL_FAMILY.all { it in keys }
        val legacy = LEGACY_FAMILY.all { it in keys }
        if (canonical == legacy) throw invalidManifest()

        if (canonical) {
            requireExact(keys, CANONICAL_REQUIRED, CANONICAL_ALLOWED, CharacterPackageImportCode.INVALID_MANIFEST)
            rejectForbidden(document, CharacterPackageImportCode.INVALID_MANIFEST, canonicalManifest = true)
            validateCanonicalShape(document)
            return Admission.Canonical(decodeCanonical(document))
        }
        return admitLegacy(document)
    }

    // MARK: - Canonical

    private fun validateCanonicalShape(document: JsonValue.Obj) {
        val assets = document.members["assets"].asObjectArray() ?: throw invalidManifest()
        for (asset in assets) {
            requireExact(
                asset.members.keys,
                setOf("path", "mediaType", "sha256"),
                setOf("path", "mediaType", "sha256"),
                CharacterPackageImportCode.INVALID_MANIFEST,
            )
        }
        document.members["motions"]?.let { motions ->
            val entries = motions.asObjectArray() ?: throw invalidManifest()
            for (motion in entries) {
                requireExact(
                    motion.members.keys,
                    setOf("motion", "animation"),
                    setOf("motion", "animation", "loop"),
                    CharacterPackageImportCode.INVALID_MANIFEST,
                )
            }
        }
        val provenance = document.members["provenance"] as? JsonValue.Obj ?: throw invalidManifest()
        requireExact(
            provenance.members.keys,
            setOf("author", "license"),
            setOf("author", "license", "source"),
            CharacterPackageImportCode.INVALID_MANIFEST,
        )
    }

    private fun decodeCanonical(document: JsonValue.Obj): CharacterPackageManifestV1 {
        val members = document.members
        val rendererName = members.text("renderer") ?: throw invalidManifest()
        val renderer = CharacterRendererKind.fromWire(rendererName) ?: throw invalidManifest()
        val locales = (members["locales"] as? JsonValue.Arr ?: throw invalidManifest())
            .elements.map { (it as? JsonValue.Text ?: throw invalidManifest()).value }
        val assets = (members["assets"] as? JsonValue.Arr ?: throw invalidManifest()).elements.map { element ->
            val asset = element as? JsonValue.Obj ?: throw invalidManifest()
            CharacterAssetV1(
                path = asset.members.text("path") ?: throw invalidManifest(),
                mediaType = asset.members.text("mediaType") ?: throw invalidManifest(),
                sha256 = asset.members.text("sha256") ?: throw invalidManifest(),
            )
        }
        val motions = members["motions"]?.takeIf { it !is JsonValue.Null }?.let { value ->
            (value as? JsonValue.Arr ?: throw invalidManifest()).elements.map { element ->
                val motion = element as? JsonValue.Obj ?: throw invalidManifest()
                CharacterMotionV1(
                    motion = motion.members.text("motion") ?: throw invalidManifest(),
                    animation = motion.members.text("animation") ?: throw invalidManifest(),
                    loop = motion.members["loop"]?.takeIf { it !is JsonValue.Null }?.let {
                        (it as? JsonValue.Bool ?: throw invalidManifest()).value
                    },
                )
            }
        }
        val provenance = members["provenance"] as? JsonValue.Obj ?: throw invalidManifest()
        return CharacterPackageManifestV1(
            schema = members.text("schema") ?: throw invalidManifest(),
            packageID = members.text("packageID") ?: throw invalidManifest(),
            characterID = members.text("characterID") ?: throw invalidManifest(),
            version = members.text("version") ?: throw invalidManifest(),
            displayName = members.text("displayName") ?: throw invalidManifest(),
            renderer = renderer,
            entryPath = members.text("entryPath") ?: throw invalidManifest(),
            portraitPath = members.optionalText("portraitPath"),
            locales = locales,
            motions = motions,
            assets = assets,
            provenance = CharacterProvenanceV1(
                author = provenance.members.text("author") ?: throw invalidManifest(),
                license = provenance.members.text("license") ?: throw invalidManifest(),
                source = provenance.members.optionalText("source"),
            ),
        )
    }

    // MARK: - Legacy

    private fun admitLegacy(document: JsonValue.Obj): Admission.LegacyPending {
        val members = document.members
        val keys = members.keys
        if (!LEGACY_FAMILY.all { it in keys } ||
            CANONICAL_EXCLUSIVE.any { it in keys } ||
            !LEGACY_ALLOWED.containsAll(keys)
        ) {
            throw unsupportedLegacy()
        }
        validateLegacyShape(document)
        rejectForbiddenLegacy(document)

        val identity = members["identity"] as? JsonValue.Obj ?: throw unsupportedLegacy()
        val appearance = members["appearance"] as? JsonValue.Obj ?: throw unsupportedLegacy()
        val characterID = members.bounded("id", 160) ?: throw unsupportedLegacy()
        val displayName = identity.members.bounded("name", 160) ?: throw unsupportedLegacy()
        val modelType = appearance.members.bounded("model_type", 32) ?: throw unsupportedLegacy()
        val renderer = CharacterRendererKind.fromWire(modelType.lowercase()) ?: throw unsupportedLegacy()

        val declaredLocale = members.text("locale")
            ?: (members["locales"] as? JsonValue.Arr)
                ?.takeIf { it.elements.size == 1 }
                ?.let { (it.elements.first() as? JsonValue.Text)?.value }
            ?: throw unsupportedLegacy()
        // One named migration, not a general locale fallback.
        val locale = if (declaredLocale == "zh") "zh-Hans" else declaredLocale
        if (locale !in CharacterPackageManifestV1.SUPPORTED_LOCALES) throw unsupportedLegacy()

        val model = appearance.members.optionalText("model")
        val portrait = appearance.members.optionalText("portrait")
        val entry = when (renderer) {
            CharacterRendererKind.STATIC -> portrait ?: throw unsupportedLegacy()
            CharacterRendererKind.LIVE2D, CharacterRendererKind.VRM -> model ?: throw unsupportedLegacy()
        }
        return Admission.LegacyPending(
            characterID = characterID,
            displayName = displayName,
            version = members.bounded("version", 80) ?: "1.0.0",
            renderer = renderer,
            entryPath = PackagePath.normalized(entry, CharacterPackageImportPhase.VALIDATE),
            portraitPath = portrait?.let { PackagePath.normalized(it, CharacterPackageImportPhase.VALIDATE) },
            locale = locale,
            warnings = if (declaredLocale == "zh") listOf("legacy_locale_zh_mapped_to_zh_Hans") else emptyList(),
        )
    }

    private fun validateLegacyShape(document: JsonValue.Obj) {
        requireSubset(document, "identity", setOf(
            "name", "avatar", "persona", "personality", "scenario", "tone", "boundaries", "system_prompt",
            "post_history_instructions", "greeting", "alternate_greetings", "example_dialogue", "description",
        ))
        requireSubset(document, "appearance", setOf(
            "model_type", "portrait", "model", "background", "accent_color", "sprite_color",
            "expressions", "motions", "lip_sync",
        ))
        requireSubset(document, "voice", setOf(
            "id", "label", "language", "prompt_language", "speed", "volume", "reference_audio",
            "prompt_text", "design", "gpt_model", "sovits_model", "emotion_map", "motion_lines",
        ))
        requireSubset(document, "knowledge", setOf("lorebook", "memory_namespace"))
        requireSubset(document, "capabilities", setOf("requested_skills", "approved_skills"))
        requireSubset(document, "creator", setOf("name", "notes"))
        requireSubset(document, "source", setOf("type", "url", "update_url"))
        requireSubset(document, "provenance", setOf("format", "file_name", "archive_sha256", "imported_at"))
        requireSubset(document, "security", setOf("license", "compatibility", "built_in", "file_hashes", "package_hash"))
    }

    /**
     * The legacy envelope legitimately contains a handful of keys the forbidden
     * walk would otherwise reject — desktop really does record a memory namespace
     * and local model weights. Those are dropped by rule rather than carried, and
     * the rest of the document still has to survive the same walk.
     */
    private fun rejectForbiddenLegacy(document: JsonValue.Obj) {
        val sanitized = document.members.toMutableMap()
        sanitized.remove("capabilities")
        sanitized.without("identity", "post_history_instructions")
        sanitized.without("appearance", "lip_sync")
        sanitized.without("voice", "gpt_model", "sovits_model")
        sanitized.without("knowledge", "memory_namespace")
        rejectForbidden(JsonValue.Obj(sanitized), CharacterPackageImportCode.UNSUPPORTED_LEGACY)
    }

    private fun MutableMap<String, JsonValue>.without(key: String, vararg dropped: String) {
        val nested = this[key] as? JsonValue.Obj ?: return
        this[key] = JsonValue.Obj(nested.members.filterKeys { it !in dropped })
    }

    private fun requireSubset(document: JsonValue.Obj, key: String, allowed: Set<String>) {
        val value = document.members[key] ?: return
        val nested = value as? JsonValue.Obj ?: throw unsupportedLegacy()
        if (!allowed.containsAll(nested.members.keys)) throw unsupportedLegacy()
    }

    // MARK: - Shared walks

    private fun rejectForbidden(
        value: JsonValue,
        code: CharacterPackageImportCode,
        depth: Int = 0,
        path: List<String> = emptyList(),
        canonicalManifest: Boolean = false,
    ) {
        if (depth > MAXIMUM_WALK_DEPTH) throw failure(code)
        when (value) {
            is JsonValue.Obj -> for ((key, child) in value.members) {
                val folded = key.lowercase().replace('-', '_')
                if (FORBIDDEN_FRAGMENTS.any { folded.contains(it) }) throw failure(code)
                rejectForbidden(child, code, depth + 1, path + key, canonicalManifest)
            }
            is JsonValue.Arr -> {
                if (value.elements.size > arrayBound(path, depth, canonicalManifest)) throw failure(code)
                for (child in value.elements) rejectForbidden(child, code, depth + 1, path, canonicalManifest)
            }
            is JsonValue.Text ->
                if (value.value.toByteArray(Charsets.UTF_8).size > MAXIMUM_STRING_BYTES) throw failure(code)
            else -> Unit
        }
    }

    /**
     * The declared asset list is the one array the contract gives a size of its
     * own: the schema's `assets.maxItems`, [CharacterPackageLimits.MAXIMUM_FILE_COUNT]
     * and the iOS tree verifier all say 2000, so the generic guard must not
     * quietly say 300 (DEC-028).
     *
     * The exemption is that array and nothing else. `depth == 1` is a member of
     * the root object, so an array nested inside an asset entry reaches here
     * carrying the same path but a greater depth, and keeps the generic bound.
     */
    private fun arrayBound(path: List<String>, depth: Int, canonicalManifest: Boolean): Int =
        if (canonicalManifest && depth == 1 && path == listOf("assets")) {
            CharacterPackageLimits.MAXIMUM_FILE_COUNT
        } else {
            MAXIMUM_ARRAY_ELEMENTS
        }

    private fun requireExact(
        actual: Set<String>,
        required: Set<String>,
        allowed: Set<String>,
        code: CharacterPackageImportCode,
    ) {
        if (!actual.containsAll(required) || !allowed.containsAll(actual)) throw failure(code)
    }

    // MARK: - Accessors

    private fun JsonValue?.asObjectArray(): List<JsonValue.Obj>? {
        val array = this as? JsonValue.Arr ?: return null
        return array.elements.map { it as? JsonValue.Obj ?: return null }
    }

    private fun Map<String, JsonValue>.text(key: String): String? = (this[key] as? JsonValue.Text)?.value

    /** Absent and explicit null both mean "not declared"; a wrong type does not. */
    private fun Map<String, JsonValue>.optionalText(key: String): String? {
        val value = this[key] ?: return null
        if (value is JsonValue.Null) return null
        return (value as? JsonValue.Text)?.value ?: throw invalidManifest()
    }

    /**
     * A non-blank string within a length bound.
     *
     * The bound counts Unicode code points. Swift counts grapheme clusters, so a
     * string built from combining sequences can measure differently on the two
     * platforms; both are far from the byte length an attacker would exploit, and
     * neither admits anything the other rejects at any realistic size. Recorded
     * rather than hidden.
     */
    private fun Map<String, JsonValue>.bounded(key: String, maximum: Int): String? {
        val value = text(key) ?: return null
        if (value.isBlank()) return null
        if (value.codePointCount(0, value.length) > maximum) return null
        return value
    }

    private fun invalidManifest() = failure(CharacterPackageImportCode.INVALID_MANIFEST)
    private fun unsupportedLegacy() = failure(CharacterPackageImportCode.UNSUPPORTED_LEGACY)

    private fun failure(code: CharacterPackageImportCode) =
        CharacterPackageImportException(code, CharacterPackageImportPhase.VALIDATE)
}
