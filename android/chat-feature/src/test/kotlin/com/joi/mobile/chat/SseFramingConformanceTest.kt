package com.joi.mobile.chat

import com.joi.mobile.character.Corpus
import com.joi.mobile.character.JsonValue
import com.joi.mobile.character.optionalList
import com.joi.mobile.character.strings
import com.joi.mobile.character.text
import java.util.Base64
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * The Android framer against `Contracts/conformance/sse-framing.json`.
 *
 * Framing is where this product has actually been bitten, on iOS, in a way that
 * unit tests over hand-written single frames could not see. The Android
 * equivalents of the API that caused it — `readLine()`, `lineSequence()`, and
 * every `Flow<String>` built on them — are more idiomatic here than the correct
 * approach is, so the vectors matter more on this platform, not less.
 */
class SseFramingConformanceTest {

    @Test
    fun `framing matches every vector`() {
        val cases = Corpus.cases("sse-framing.json")
        assertTrue(cases.size >= 15, "corpus shrank to ${cases.size} cases")

        for (case in cases) {
            val parser = SseFrameParser()
            val payloads = mutableListOf<String>()
            for (byte in bytesOf(case)) {
                parser.consume(byte)?.let(payloads::add)
            }
            parser.finish()?.let(payloads::add)

            assertEquals(
                case.strings("payloads"),
                payloads,
                "framing diverged for ${case.text("id")}",
            )
        }
    }

    /**
     * Feeding the whole stream as one run must give the same answer as feeding it
     * in the authored chunks. A framer holding per-chunk state passes the vectors
     * as written and fails here.
     */
    @Test
    fun `chunk boundaries are not semantic`() {
        for (case in Corpus.cases("sse-framing.json")) {
            val whole = bytesOf(case)
            val parser = SseFrameParser()
            val payloads = mutableListOf<String>()
            whole.forEach { byte -> parser.consume(byte)?.let(payloads::add) }
            parser.finish()?.let(payloads::add)
            assertEquals(case.strings("payloads"), payloads, case.text("id"))
        }
    }

    private fun bytesOf(case: JsonValue.Obj): ByteArray {
        case.optionalList("chunksBase64")?.let { encoded ->
            return encoded.fold(ByteArray(0)) { accumulated, chunk ->
                accumulated + Base64.getDecoder().decode((chunk as JsonValue.Text).value)
            }
        }
        return case.strings("chunks").joinToString("").toByteArray(Charsets.UTF_8)
    }
}
