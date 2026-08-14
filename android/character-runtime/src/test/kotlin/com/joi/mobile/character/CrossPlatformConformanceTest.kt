package com.joi.mobile.character

import com.joi.mobile.core.CharacterPackageLimits
import java.io.File
import java.util.Base64
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue
import kotlin.test.fail

/**
 * The Android core against `Contracts/conformance/`.
 *
 * This is the whole argument for the corpus. The same vectors, run by two
 * implementations that share no code, in a lane fast enough that a divergence is
 * found while it is still cheap — before a package installs under two different
 * identities on two platforms, and before a stream framer that works in a unit
 * test fails on every live turn.
 */
class CrossPlatformConformanceTest {

    // MARK: - Content identity

    @Test
    fun `content identity matches every vector`() {
        val cases = Corpus.cases("content-id.json")
        assertTrue(cases.size >= 8, "corpus shrank to ${cases.size} cases")

        for (case in cases) {
            val entries = case.list("files").map { it as JsonValue.Obj }.map { file ->
                val bytes = Base64.getDecoder().decode(file.text("base64"))
                ContentTreeIdentity.Entry(
                    path = file.text("path"),
                    sizeBytes = bytes.size.toLong(),
                    sha256Hex = ContentTreeIdentity.sha256Of(bytes),
                )
            }
            assertEquals(
                case.text("contentID"),
                ContentTreeIdentity.of(entries),
                "content identity diverged for ${case.text("id")}",
            )
        }
    }

    /**
     * The same vectors through a real directory, so filesystem behaviour is
     * covered too and not only the arithmetic. This is where a platform that
     * hands back decomposed filenames would be caught.
     */
    @Test
    fun `content identity of a materialised tree matches every vector`() {
        for (case in Corpus.cases("content-id.json")) {
            val root = createTempDirectory()
            try {
                for (file in case.list("files").map { it as JsonValue.Obj }) {
                    val target = File(root, file.text("path"))
                    target.parentFile.mkdirs()
                    target.writeBytes(Base64.getDecoder().decode(file.text("base64")))
                }
                assertEquals(
                    case.text("contentID"),
                    ContentTreeIdentity.ofDirectory(root),
                    "materialised tree diverged for ${case.text("id")}",
                )
            } finally {
                root.deleteRecursively()
            }
        }
    }

    /**
     * Kotlin's `sorted()` orders by UTF-16 code units. The contract orders by
     * UTF-8 bytes. They disagree exactly when a supplementary-plane character
     * meets one in U+E000–U+FFFF, which is why the corpus carries that case and
     * why this asserts the two orderings really are different — a test that only
     * checked the digest would still pass if someone quietly "simplified" the
     * comparator on a machine whose corpus had no such vector.
     */
    @Test
    fun `path ordering is by utf8 bytes and not by the platform default`() {
        val paths = listOf("Ａ.txt", "🎏.txt", "manifest.json")
        assertEquals(
            listOf("manifest.json", "Ａ.txt", "🎏.txt"),
            paths.sortedWith(ContentTreeIdentity.pathOrder),
        )
        assertEquals(
            listOf("manifest.json", "🎏.txt", "Ａ.txt"),
            paths.sorted(),
            "if this stops differing the vector has lost its purpose",
        )
    }

    // MARK: - Strict JSON

    @Test
    fun `strict json scanner matches every vector`() {
        val cases = Corpus.cases("strict-json.json")
        assertTrue(cases.size >= 30, "corpus shrank to ${cases.size} cases")

        for (case in cases) {
            val bytes = case.text("document").toByteArray(Charsets.UTF_8)
            val expected = case.text("expect")
            if (expected == "accept") {
                StrictJson.objectOf(bytes)
                continue
            }
            val failure = assertFailsWith<CharacterPackageImportException>(
                "${case.text("id")} should have been refused as $expected",
            ) { StrictJson.objectOf(bytes) }
            assertEquals(expected, failure.code.wireName, "wrong code for ${case.text("id")}")
        }
    }

    // MARK: - Manifest admission

    @Test
    fun `manifest admission matches every vector`() {
        val cases = Corpus.cases("manifest-validation.json")
        assertTrue(cases.size >= 30, "corpus shrank to ${cases.size} cases")

        for (case in cases) {
            val bytes = case.text("document").toByteArray(Charsets.UTF_8)
            val expected = case.text("expect")
            if (expected == "accept") {
                val admission = CharacterManifestAdmission.admit(bytes)
                assertTrue(
                    admission is CharacterManifestAdmission.Admission.Canonical,
                    "${case.text("id")} should have been admitted as canonical",
                )
                continue
            }
            try {
                CharacterManifestAdmission.admit(bytes)
                fail("${case.text("id")} should have been refused as $expected")
            } catch (failure: CharacterPackageImportException) {
                assertEquals(expected, failure.code.wireName, "wrong code for ${case.text("id")}")
            }
        }
    }

    // MARK: - The declared asset list (DEC-028)

    /**
     * The twin of the Swift suite's boundary test, and the one rule in
     * `manifest-validation.json` that is stated in its `notes` instead of carried
     * as a vector: 2000 declared assets is a quarter of a megabyte of filler, and
     * a corpus case that large would be read by nobody. Both platforms therefore
     * pin the numbers in their own suite, and both must pin the same ones.
     */
    @Test
    fun `declared asset list is bounded by the contract and not by the generic array guard`() {
        assertEquals(2_000, CharacterPackageLimits.MAXIMUM_FILE_COUNT, "the contract's number moved")
        for (count in listOf(1, 300, 301, CharacterPackageLimits.MAXIMUM_FILE_COUNT)) {
            CharacterManifestAdmission.admit(manifestBytes(count))
        }
        val failure = assertFailsWith<CharacterPackageImportException>(
            "one past the contract's file count is the refusal",
        ) { CharacterManifestAdmission.admit(manifestBytes(CharacterPackageLimits.MAXIMUM_FILE_COUNT + 1)) }
        assertEquals(CharacterPackageImportCode.INVALID_MANIFEST, failure.code)
    }

    /**
     * The exemption is that array and nothing else. Both of these were bounded at
     * 300 before DEC-028 and must stay bounded at 300 after it, or the fix has
     * removed a guard rather than corrected it.
     */
    @Test
    fun `every other array keeps the generic bound`() {
        val manyLocales = List(301) { "\"zh-Hans\"" }.joinToString(",")
        assertEquals(
            CharacterPackageImportCode.INVALID_MANIFEST,
            assertFailsWith<CharacterPackageImportException> {
                CharacterManifestAdmission.admit(manifestBytes(1, locales = manyLocales))
            }.code,
            "a 301-element `locales`",
        )

        val pathAsAnArray = List(301) { "\"x\"" }.joinToString(",")
        val digest = "0".repeat(64)
        val nestedInsideAnAsset =
            """{"path":[$pathAsAnArray],"mediaType":"application/json","sha256":"$digest"}"""
        assertEquals(
            CharacterPackageImportCode.INVALID_MANIFEST,
            assertFailsWith<CharacterPackageImportException> {
                CharacterManifestAdmission.admit(manifestBytes(0, extraAssets = nestedInsideAnAsset))
            }.code,
            "an array nested inside an asset entry is not the declared asset list",
        )
    }

    /**
     * A count bound the document size makes unreachable is not a bound anyone can
     * use: before DEC-028 a manifest declaring the contract's own file count was
     * refused for bytes, well before the count was ever examined.
     *
     * The one place the two platforms answer differently is above that byte
     * bound. iOS reaches it through a bounded read of `manifest.json` and reports
     * `unsafeArchive`; this layer is handed the document and reports
     * `invalidManifest` from the scanner. That is the read-path boundary the
     * corpus already excludes from this stage, not a new divergence — recorded in
     * DEC-028 rather than left to be rediscovered.
     */
    @Test
    fun `the full declared asset count fits within the manifest byte bound`() {
        val realistic = manifestBytes(CharacterPackageLimits.MAXIMUM_FILE_COUNT, pathLength = 28)
        assertTrue(realistic.size <= CharacterPackageLimits.MAXIMUM_MANIFEST_BYTES)
        CharacterManifestAdmission.admit(realistic)

        val overlong = manifestBytes(CharacterPackageLimits.MAXIMUM_FILE_COUNT, pathLength = 512)
        assertTrue(overlong.size > CharacterPackageLimits.MAXIMUM_MANIFEST_BYTES)
        assertEquals(
            CharacterPackageImportCode.INVALID_MANIFEST,
            assertFailsWith<CharacterPackageImportException> {
                CharacterManifestAdmission.admit(overlong)
            }.code,
            "2000 assets at the maximum path length is over a megabyte of manifest",
        )
    }

    /** A canonical Live2D manifest declaring `assetCount` assets. */
    private fun manifestBytes(
        assetCount: Int,
        pathLength: Int = 12,
        locales: String = "\"zh-Hans\"",
        extraAssets: String = "",
    ): ByteArray {
        val digest = "0".repeat(64)
        val declared = (0 until assetCount).map { index ->
            val stem = "motions/%05d".format(index)
            val path = stem + "x".repeat(maxOf(0, pathLength - stem.length))
            """{"path":"$path","mediaType":"application/json","sha256":"$digest"}"""
        }
        val assets = (declared + listOfNotNull(extraAssets.takeIf { it.isNotEmpty() })).joinToString(",")
        return (
            """{"schema":"joi.character.v1","packageID":"fixture.live2d",""" +
                """"characterID":"fixture.live2d","version":"1.0.0","displayName":"Fixture",""" +
                """"renderer":"live2d","entryPath":"model.model3.json","locales":[$locales],""" +
                """"assets":[$assets],"provenance":{"author":"Joi Mobile fixture",""" +
                """"license":"Repository test metadata only"}}"""
            ).toByteArray(Charsets.UTF_8)
    }

    @Test
    fun `every expected code is a stable import code`() {
        for (name in listOf("strict-json.json", "manifest-validation.json")) {
            for (case in Corpus.cases(name)) {
                val expected = case.text("expect")
                if (expected == "accept") continue
                assertTrue(
                    CharacterPackageImportCode.fromWire(expected) != null,
                    "$name/${case.text("id")} expects unknown code $expected",
                )
            }
        }
    }

    private fun createTempDirectory(): File =
        File.createTempFile("joi-conformance-", "").let { file ->
            file.delete()
            file.mkdirs()
            file
        }
}
