package com.joi.mobile.app

import com.joi.mobile.core.CharacterSelection
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertSame
import kotlin.test.assertTrue

/**
 * The Android twin of the iOS suite's first-slice case: switching between the
 * two primary surfaces preserves character, thread, session and transcript.
 *
 * It is a plain JVM test with no Android dependency, because the rule it checks
 * is a product rule and not a UI one. A two-surface companion that loses its
 * conversation on a tab change has stopped being one companion, and that is
 * exactly the bug a device test would find too late.
 */
class CompanionSessionStoreTest {

    private val joi = CharacterSelection(characterID = "joi.starter", displayName = "Joi")
    private val other = CharacterSelection(characterID = "joi.guide", displayName = "向导")

    private fun store(
        surface: CompanionSurface = CompanionSurface.CHAT,
        transcript: List<TranscriptLine> = emptyList(),
    ) = CompanionSessionStore(
        CompanionSessionState(
            surface = surface,
            character = joi,
            threadID = "thread.1",
            sessionID = "session.1",
            acceptedTranscript = transcript,
        )
    )

    @Test
    fun `switching surface preserves character thread session and transcript`() {
        val line = TranscriptLine("event.1", Speaker.COMPANION, "今天想去哪里？")
        val store = store(transcript = listOf(line))
        val before = store.state

        store.show(CompanionSurface.MAP)

        assertEquals(CompanionSurface.MAP, store.state.surface)
        assertEquals(before.character, store.state.character)
        assertEquals(before.threadID, store.state.threadID)
        assertEquals(before.sessionID, store.state.sessionID)
        assertEquals(before.acceptedTranscript, store.state.acceptedTranscript)
    }

    @Test
    fun `switching to the surface already showing changes nothing and notifies nobody`() {
        val store = store()
        var notifications = 0
        store.observe { notifications += 1 }
        val before = store.state

        store.show(CompanionSurface.CHAT)

        assertSame(before, store.state)
        assertEquals(0, notifications, "a no-op switch must not wake the view layer")
    }

    @Test
    fun `changing character keeps the conversation`() {
        val line = TranscriptLine("event.1", Speaker.USER, "你好")
        val store = store(transcript = listOf(line))

        store.activate(other)

        assertEquals(other, store.state.character)
        assertEquals("thread.1", store.state.threadID)
        assertEquals(listOf(line), store.state.acceptedTranscript)
    }

    @Test
    fun `a repeated eventID is the same line arriving twice`() {
        val store = store()
        val line = TranscriptLine("event.1", Speaker.USER, "你好")

        store.append(line)
        store.append(line.copy(displayText = "你好（重发）"))

        assertEquals(1, store.state.acceptedTranscript.size)
        assertEquals("你好", store.state.acceptedTranscript.single().displayText)
    }

    @Test
    fun `observers see every published state and can unsubscribe`() {
        val store = store()
        val seen = mutableListOf<CompanionSurface>()
        val cancel = store.observe { seen += it.surface }

        store.show(CompanionSurface.MAP)
        cancel()
        store.show(CompanionSurface.CHAT)

        assertEquals(listOf(CompanionSurface.MAP), seen)
        assertTrue(store.state.surface == CompanionSurface.CHAT, "the store still advances after unsubscribe")
    }
}
