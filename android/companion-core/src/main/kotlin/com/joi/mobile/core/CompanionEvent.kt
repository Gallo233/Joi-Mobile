package com.joi.mobile.core

/**
 * `joi.companion-event.v1` — the only shape a client ever sees from the official
 * proxy. Transcribed from `Contracts/companion-event-v1.schema.json`.
 *
 * Two fields carry a product decision worth restating where a reader will meet
 * them: [displayText] and [voiceLine] are separate because Joi shows Simplified
 * Chinese and speaks Japanese in the character's own voice. Treating them as one
 * string forces a choice between the audience and the character.
 */
data class CompanionEventV1(
    val schema: String = SCHEMA,
    val eventID: String,
    val requestID: String,
    val threadID: String,
    val sessionID: String,
    val characterID: String,
    val timestamp: String,
    val phase: CompanionPhase,
    val contentState: CompanionContentState,
    val displayText: String? = null,
    val voiceLine: String? = null,
    val memoryEligibility: MemoryEligibility,
    val sources: List<SourceProjectionV1> = emptyList(),
    val errorCode: String? = null,
) {
    companion object {
        const val SCHEMA = "joi.companion-event.v1"
    }
}

enum class CompanionPhase(val wireName: String) {
    IDLE("idle"),
    RECEIVED("received"),
    UNDERSTANDING("understanding"),
    THINKING("thinking"),
    ACTING("acting"),
    WAITING("waiting"),
    PAUSED("paused"),
    DONE("done"),
    FAILED("failed");

    companion object {
        fun fromWire(value: String): CompanionPhase? = entries.firstOrNull { it.wireName == value }
    }
}

enum class CompanionContentState(val wireName: String) {
    PARTIAL("partial"),

    /**
     * The turn's user message, echoed by the backend. A user message becomes a
     * transcript line only here — never locally at send time — so "appended
     * exactly once" is checkable rather than hopeful.
     */
    ACCEPTED_INPUT("acceptedInput"),
    STREAMING_DRAFT("streamingDraft"),
    ACCEPTED_FINAL("acceptedFinal"),
    CANCELLED("cancelled"),
    FAILED("failed");

    companion object {
        fun fromWire(value: String): CompanionContentState? =
            entries.firstOrNull { it.wireName == value }
    }
}

enum class MemoryEligibility(val wireName: String) {
    NONE("none"),
    PROPOSAL_ALLOWED("proposalAllowed");

    companion object {
        fun fromWire(value: String): MemoryEligibility? =
            entries.firstOrNull { it.wireName == value }
    }
}

data class SourceProjectionV1(
    val placeID: String?,
    val claimID: String,
    val identityConfidence: Double?,
    val claimSupportConfidence: Double,
    val publisher: String,
    val title: String,
    val locator: String,
    val authority: SourceAuthority,
    val revision: String,
    val retrievedAt: String,
    val conflictStatus: ConflictStatus,
    val correctionStatus: CorrectionStatus,
    val rights: String,
    val withdrawn: Boolean,
)

enum class SourceAuthority(val wireName: String) {
    PRIMARY("primary"),
    OFFICIAL("official"),
    INSTITUTIONAL("institutional"),
    SECONDARY("secondary"),
    COMMUNITY("community");

    companion object {
        fun fromWire(value: String): SourceAuthority? = entries.firstOrNull { it.wireName == value }
    }
}

enum class ConflictStatus(val wireName: String) {
    NONE("none"),
    DISPUTED("disputed"),
    UNRESOLVED("unresolved"),
    RESOLVED("resolved");

    companion object {
        fun fromWire(value: String): ConflictStatus? = entries.firstOrNull { it.wireName == value }
    }
}

enum class CorrectionStatus(val wireName: String) {
    CURRENT("current"),
    CORRECTED("corrected"),
    RETRACTED("retracted"),
    PENDING_REVIEW("pendingReview");

    companion object {
        fun fromWire(value: String): CorrectionStatus? = entries.firstOrNull { it.wireName == value }
    }
}

/**
 * Stable codes the client may receive for an upstream problem. The provider and
 * model behind the proxy are server-side facts and never appear on the wire, so
 * swapping providers stays a backend change with no client release.
 */
object StableUpstreamCodes {
    const val UNAVAILABLE = "upstream_unavailable"
    const val REJECTED = "upstream_rejected"
    const val MALFORMED = "upstream_malformed"

    val all = setOf(UNAVAILABLE, REJECTED, MALFORMED)
}
