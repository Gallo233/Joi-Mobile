package com.joi.mobile.chat

/**
 * Incremental server-sent-event framer.
 *
 * This exists for a reason worth stating on both platforms: the obvious
 * convenience API for reading a stream line by line does not emit empty lines,
 * and a blank line is precisely what terminates an SSE frame. Using one
 * concatenates consecutive events into a single invalid payload. On iOS that was
 * `AsyncSequence.lines`; on Android it is `BufferedReader.readLine()`, `lineSequence()`
 * and every `Flow<String>` built on them. The failure is identical: unit tests
 * over hand-written single frames pass while every live turn fails.
 *
 * Fed one byte at a time so a chunk boundary can fall anywhere, including inside
 * a multi-byte character. Pinned by `Contracts/conformance/sse-framing.json`.
 */
class SseFrameParser {
    private val lineBytes = ArrayList<Byte>()
    private val dataLines = ArrayList<String>()

    /**
     * Feeds one byte. Returns the accumulated `data:` payload when a blank line
     * closes a frame, and null otherwise.
     */
    fun consume(byte: Byte): String? {
        if (byte == NEWLINE) return closeLine()
        lineBytes.add(byte)
        if (lineBytes.size > MAXIMUM_LINE_BYTES) throw MalformedStreamException()
        return null
    }

    /**
     * Flushes a stream that ended without a terminating blank line. A complete
     * final frame is still delivered; a partial one yields null.
     */
    fun finish(): String? {
        if (lineBytes.isNotEmpty()) {
            closeLine()?.let { return it }
        }
        return closeFrame()
    }

    private fun closeLine(): String? {
        // Tolerate CRLF: the CR belongs to the delimiter, not the payload.
        if (lineBytes.isNotEmpty() && lineBytes.last() == CARRIAGE_RETURN) {
            lineBytes.removeAt(lineBytes.size - 1)
        }
        val line = String(lineBytes.toByteArray(), Charsets.UTF_8)
        lineBytes.clear()

        if (line.isEmpty()) return closeFrame()
        // `id:` and `event:` are read and discarded: the payload itself carries
        // the authoritative event, request and thread identity, and a second
        // transport-level id would be a weaker source of the same truth.
        fieldValue(line, "data:")?.let { dataLines.add(it) }
        return null
    }

    private fun closeFrame(): String? {
        if (dataLines.isEmpty()) return null
        val payload = dataLines.joinToString("\n")
        dataLines.clear()
        return if (payload.isEmpty()) null else payload
    }

    class MalformedStreamException : Exception("sse line exceeded the frame bound")

    companion object {
        /** A line longer than this is a malformed stream rather than something to buffer without bound. */
        const val MAXIMUM_LINE_BYTES = 512 * 1024

        private val NEWLINE = '\n'.code.toByte()
        private val CARRIAGE_RETURN = '\r'.code.toByte()

        /**
         * The value after an SSE field prefix. Exactly one leading space is
         * structural per the SSE grammar; any further space belongs to the
         * payload.
         */
        fun fieldValue(line: String, prefix: String): String? {
            if (!line.startsWith(prefix)) return null
            val value = line.substring(prefix.length)
            return if (value.startsWith(" ")) value.substring(1) else value
        }
    }
}
