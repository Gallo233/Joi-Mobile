package com.joi.mobile.core

/**
 * The character package contract, in Kotlin.
 *
 * This is a transcription of `Packages/CompanionCore/Sources/CompanionCore/CharacterContracts.swift`
 * against the same JSON Schema, not an independent design. Where the two ever
 * disagree, `Contracts/character-package-manifest-v1.schema.json` and
 * `Contracts/conformance/` decide, because those are the artifacts both
 * platforms are tested against.
 */

/**
 * How a character is drawn. Closed on every platform: a package declaring
 * anything else is refused rather than degraded, so an unsupported renderer can
 * never be silently reinterpreted as a supported one.
 */
enum class CharacterRendererKind(val wireName: String) {
    STATIC("static"),
    LIVE2D("live2d"),
    VRM("vrm");

    companion object {
        fun fromWire(value: String): CharacterRendererKind? =
            entries.firstOrNull { it.wireName == value }
    }
}

/** An installation of a package, distinct from the content it holds. */
@JvmInline
value class CharacterInstallationID(val rawValue: String)

/**
 * A package's content, identified by what it *is* rather than by where it sits.
 * Two imports of the same bytes carry the same value; a mutated tree does not.
 */
@JvmInline
value class CharacterContentID(val rawValue: String)

/**
 * Who the companion currently is.
 *
 * Both surfaces read this from one owner, and it carries the installation and
 * content identity as well as the display name so that "which character" and
 * "which bytes" can never drift apart. Both are null for the bundled static
 * identity, which is not an installed package.
 */
data class CharacterSelection(
    val characterID: String,
    val displayName: String,
    val installationID: CharacterInstallationID? = null,
    val contentID: CharacterContentID? = null,
)

/** One declared file, its declared media type, and the digest that must match it. */
data class CharacterAssetV1(
    val path: String,
    val mediaType: String,
    val sha256: String,
)

/**
 * One semantic motion and the animation clip that performs it.
 *
 * A `.vrm` file carries a rig and no animation whatsoever, so a VRM character's
 * idle, greeting and dance clips are separate `.vrma` assets. This table is both
 * the product-facing name map and the renderer graph that decides which
 * animation files may enter runtime content. Only a VRM package may declare it.
 */
data class CharacterMotionV1(
    val motion: String,
    val animation: String,
    val loop: Boolean? = null,
) {
    val loops: Boolean get() = loop ?: false

    companion object {
        /** The motion a character holds between events. */
        const val IDLE_NAME = "idle"
    }
}

/** Who made the character and under what terms. Never optional: a package with no declared licence has no admissible rights state. */
data class CharacterProvenanceV1(
    val author: String,
    val license: String,
    val source: String? = null,
)

data class CharacterPackageManifestV1(
    val schema: String = SCHEMA,
    val packageID: String,
    val characterID: String,
    val version: String,
    val displayName: String,
    val renderer: CharacterRendererKind,
    val entryPath: String,
    val portraitPath: String? = null,
    val locales: List<String>,
    /** Null when the package predates the motion table; read it through [declaredMotions]. */
    val motions: List<CharacterMotionV1>? = null,
    val assets: List<CharacterAssetV1>,
    val provenance: CharacterProvenanceV1,
) {
    val declaredMotions: List<CharacterMotionV1> get() = motions ?: emptyList()

    companion object {
        const val SCHEMA = "joi.character.v1"

        /** The display and content locales a package may declare. */
        val SUPPORTED_LOCALES = setOf("zh-Hans", "zh-Hant", "en", "ja", "ko")
    }
}

/** Limits shared with the iOS runtime and with the manifest schema. */
object CharacterPackageLimits {
    const val MAXIMUM_ARCHIVE_BYTES: Long = 128L * 1024 * 1024
    const val MAXIMUM_FILE_BYTES: Long = 128L * 1024 * 1024
    const val MAXIMUM_EXPANDED_BYTES: Long = 512L * 1024 * 1024
    const val MAXIMUM_FILE_COUNT: Int = 2_000
    const val MAXIMUM_EXPANSION_RATIO: Int = 20
    const val MAXIMUM_MOTION_COUNT: Int = 64

    /**
     * The manifest document itself. Sized so [MAXIMUM_FILE_COUNT] declared assets
     * fit at any path length a real package uses, because a byte bound that bit
     * first would cap the declared asset count at a number the contract never
     * states — and would report it as `unsafeArchive` (DEC-028).
     */
    const val MAXIMUM_MANIFEST_BYTES: Int = 1024 * 1024
}
