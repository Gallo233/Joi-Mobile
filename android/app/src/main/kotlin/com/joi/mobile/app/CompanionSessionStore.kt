package com.joi.mobile.app

import com.joi.mobile.core.CharacterSelection

/** Which primary surface is showing. There are two, and there will be two. */
enum class CompanionSurface { CHAT, MAP }

/**
 * Everything Chat and Map agree about.
 *
 * Chat and Map are surfaces over one companion, not two features that happen to
 * share a tab bar: the character, the conversation thread and the session are
 * the same on both, and switching between them is a presentation change and
 * nothing else.
 */
data class CompanionSessionState(
    val surface: CompanionSurface,
    val character: CharacterSelection,
    val threadID: String,
    val sessionID: String,
    val acceptedTranscript: List<TranscriptLine>,
)

data class TranscriptLine(val eventID: String, val speaker: Speaker, val displayText: String)

enum class Speaker { USER, COMPANION }

/**
 * The single writer of the active character and the accepted transcript.
 *
 * The rule is carried over unchanged from iOS: one owner, so a late callback, a
 * cancellation or a surface switch cannot overwrite a newer selection or split
 * Chat and Map identity. Views derive what they show from a snapshot of this
 * state and keep no second mutable copy of the current character.
 *
 * Deliberately free of any Android import so the rule is testable on the JVM in
 * milliseconds rather than on a device.
 */
class CompanionSessionStore(initial: CompanionSessionState) {

    var state: CompanionSessionState = initial
        private set

    private val observers = mutableListOf<(CompanionSessionState) -> Unit>()

    fun observe(observer: (CompanionSessionState) -> Unit): () -> Unit {
        observers += observer
        return { observers -= observer }
    }

    /**
     * Shows the other surface. It touches nothing else, which is the whole
     * point — the iOS suite asserts the same property, and it is the first
     * thing a two-surface product gets wrong.
     */
    fun show(surface: CompanionSurface) {
        if (state.surface == surface) return
        publish(state.copy(surface = surface))
    }

    /**
     * Switches the active character. Thread, session and accepted transcript
     * survive: changing who is speaking does not end the conversation.
     */
    fun activate(character: CharacterSelection) {
        if (state.character == character) return
        publish(state.copy(character = character))
    }

    /**
     * Appends a line the backend has accepted.
     *
     * A user message becomes a transcript line here and only here — never
     * locally at send time — so "appended exactly once" is checkable instead of
     * hopeful. A repeated `eventID` is the same line arriving twice and is
     * dropped rather than de-duplicated by guesswork later.
     */
    fun append(line: TranscriptLine) {
        if (state.acceptedTranscript.any { it.eventID == line.eventID }) return
        publish(state.copy(acceptedTranscript = state.acceptedTranscript + line))
    }

    private fun publish(next: CompanionSessionState) {
        state = next
        observers.toList().forEach { it(next) }
    }
}
