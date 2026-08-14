package com.joi.mobile.character

import java.text.Normalizer

/**
 * What a package-relative path may be.
 *
 * Every path that reaches the filesystem passes through here first, whether it
 * came from an archive entry, a manifest declaration or a renderer graph. The
 * rules are deliberately narrower than the platform's: an absolute path, a
 * traversal, a backslash, a drive-letter colon, an empty or dot component and
 * any control character are refused outright rather than sanitized, because a
 * sanitized hostile path is still a path somebody chose for a reason.
 */
object PackagePath {
    const val MAXIMUM_BYTES = 512

    /**
     * Returns the NFC form of [path], or throws if the path is not one a package
     * may contain.
     *
     * Callers compare the result against the input **byte for byte**. Kotlin's
     * `==` does that; Swift's does not — Swift `String` equality is canonical, so
     * on iOS this comparison passes for a decomposed path and the composed form
     * is what the caller keeps. That difference is the subject of DEC-026.
     */
    fun normalized(path: String, phase: CharacterPackageImportPhase = CharacterPackageImportPhase.PREFLIGHT): String {
        val bytes = path.toByteArray(Charsets.UTF_8).size
        if (path.isEmpty() ||
            bytes > MAXIMUM_BYTES ||
            path.startsWith("/") ||
            path.startsWith("\\") ||
            path.contains("\\") ||
            path.contains(":") ||
            path.codePoints().anyMatch { it == 0 || it < 0x20 || it == 0x7F }
        ) {
            throw unsafe(phase)
        }
        val isDirectory = path.endsWith("/")
        val body = if (isDirectory) path.dropLast(1) else path
        val parts = body.split("/")
        if (parts.isEmpty() || parts.any { it.isEmpty() || it == "." || it == ".." }) throw unsafe(phase)
        val normalized = Normalizer.normalize(body, Normalizer.Form.NFC)
        if (normalized.toByteArray(Charsets.UTF_8).size > MAXIMUM_BYTES) throw unsafe(phase)
        return normalized + if (isDirectory) "/" else ""
    }

    /**
     * The key two paths collide on. Case folding is deliberate: a case-insensitive
     * volume would let `Model.vrm` and `model.vrm` become one file after the
     * manifest had already accounted for two.
     */
    fun collisionKey(path: String): String =
        Normalizer.normalize(path, Normalizer.Form.NFC).lowercase()

    private fun unsafe(phase: CharacterPackageImportPhase) =
        CharacterPackageImportException(CharacterPackageImportCode.UNSAFE_ARCHIVE, phase)
}
