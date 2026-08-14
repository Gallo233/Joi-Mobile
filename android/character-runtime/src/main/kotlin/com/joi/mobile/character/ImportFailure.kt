package com.joi.mobile.character

/**
 * The closed set of reasons a character package can be refused.
 *
 * These are product surface, not diagnostics: each one selects the sentence the
 * user reads. They are identical on every platform, which is why
 * `Contracts/conformance/manifest-validation.json` asserts on the code and not
 * merely on "it failed", and why `Tests/test_conformance_corpus.py` reads this
 * set out of the Swift declaration and refuses a vector naming anything else.
 */
enum class CharacterPackageImportCode(val wireName: String) {
    MALFORMED_ARCHIVE("malformedArchive"),
    UNSAFE_ARCHIVE("unsafeArchive"),
    UNSUPPORTED_ARCHIVE("unsupportedArchive"),

    /** Safe but outside the supported ZIP profile. Deliberately distinct from a corrupt archive: the user can act on one and not on the other. */
    UNSUPPORTED_ARCHIVE_PROFILE("unsupportedArchiveProfile"),
    INVALID_MANIFEST("invalidManifest"),
    UNSUPPORTED_LEGACY("unsupportedLegacy"),
    HASH_MISMATCH("hashMismatch"),
    INVALID_RENDERER("invalidRenderer"),
    SOURCE_CHANGED("sourceChanged"),
    RIGHTS_UNVERIFIED("rightsUnverified"),
    STALE_HANDLE("staleHandle"),
    IN_USE("inUse"),
    RECOVERY_REQUIRED("recoveryRequired"),
    INSTALL_FAILED("installFailed"),
    NOT_FOUND("notFound");

    companion object {
        fun fromWire(value: String): CharacterPackageImportCode? =
            entries.firstOrNull { it.wireName == value }
    }
}

enum class CharacterPackageImportPhase(val wireName: String) {
    SELECT("select"),
    PREFLIGHT("preflight"),
    STAGE("stage"),
    VALIDATE("validate"),
    SEAL("seal"),
    COMMIT("commit"),
    ACTIVATION("activation"),
    REMOVAL("removal"),
    RECOVERY("recovery"),
}

/**
 * Carries a code and the phase it came from, and deliberately nothing else — no
 * path, no payload, no underlying exception, no localized text. An import
 * failure that quoted the offending path would put a user-chosen filesystem
 * location into logs and crash reports.
 */
class CharacterPackageImportException(
    val code: CharacterPackageImportCode,
    val phase: CharacterPackageImportPhase,
) : Exception("${code.wireName}@${phase.wireName}") {
    override fun toString(): String = "CharacterPackageImportException(${code.wireName}, ${phase.wireName})"
}
