package com.joi.mobile.character

import com.joi.mobile.core.CharacterPackageLimits
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.nio.charset.CharacterCodingException
import java.nio.charset.CodingErrorAction

/**
 * A JSON value, kept deliberately small: a manifest is a configuration document,
 * not a data format, and nothing here needs a general-purpose object mapper.
 */
sealed interface JsonValue {
    data class Obj(val members: Map<String, JsonValue>) : JsonValue
    data class Arr(val elements: List<JsonValue>) : JsonValue
    data class Text(val value: String) : JsonValue

    /** Kept as its literal so no manifest value is silently widened or rounded on the way in. */
    data class Num(val literal: String) : JsonValue
    data class Bool(val value: Boolean) : JsonValue
    data object Null : JsonValue
}

/**
 * The owned strict JSON scanner.
 *
 * Joi does not parse manifests with a platform JSON API — not `JSONObject`, not
 * Gson, not kotlinx.serialization — for one reason: every mainstream parser
 * silently accepts a duplicate key and keeps the last one. A manifest whose
 * meaning depends on which copy of `renderer` won is not a manifest, and a
 * document that installs as a VRM package while its author reads it as static is
 * the whole attack.
 *
 * Everything this accepts and refuses is pinned by
 * `Contracts/conformance/strict-json.json`, which the iOS scanner runs too.
 */
object StrictJson {
    /** Nested containers. A recursive-descent parser without this bound meets a hostile document with a stack overflow instead of a code. */
    const val MAXIMUM_DEPTH = 64

    fun objectOf(
        bytes: ByteArray,
        maximumBytes: Int = CharacterPackageLimits.MAXIMUM_MANIFEST_BYTES,
        phase: CharacterPackageImportPhase = CharacterPackageImportPhase.VALIDATE,
    ): JsonValue.Obj {
        val value = valueOf(bytes, maximumBytes, phase)
        return value as? JsonValue.Obj
            ?: throw CharacterPackageImportException(CharacterPackageImportCode.INVALID_MANIFEST, phase)
    }

    /** Parses any top-level value. Manifests must be objects; this is the shared entry point. */
    fun valueOf(
        bytes: ByteArray,
        maximumBytes: Int = CharacterPackageLimits.MAXIMUM_MANIFEST_BYTES,
        phase: CharacterPackageImportPhase = CharacterPackageImportPhase.VALIDATE,
    ): JsonValue {
        if (bytes.size > maximumBytes) {
            throw CharacterPackageImportException(CharacterPackageImportCode.INVALID_MANIFEST, phase)
        }
        return Scanner(bytes, phase).scanDocument()
    }

    private val QUOTE = '"'.code
    private val BACKSLASH = '\\'.code
    private val OPEN_BRACE = '{'.code
    private val CLOSE_BRACE = '}'.code
    private val OPEN_BRACKET = '['.code
    private val CLOSE_BRACKET = ']'.code
    private val COLON = ':'.code
    private val COMMA = ','.code
    private val MINUS = '-'.code
    private val PLUS = '+'.code
    private val PERIOD = '.'.code
    private val ZERO = '0'.code
    private val NINE = '9'.code

    private class Scanner(private val bytes: ByteArray, private val phase: CharacterPackageImportPhase) {
        private var index = 0

        /** Bytes are read as unsigned so every comparison below is against an ASCII code point. */
        private fun at(offset: Int): Int = bytes[offset].toInt() and 0xFF

        fun scanDocument(): JsonValue {
            skipWhitespace()
            val value = scanValue(0)
            skipWhitespace()
            // Trailing content is refused rather than ignored: a second document
            // after the first is not a manifest with a note on the end.
            if (index != bytes.size) throw fail()
            return value
        }

        private fun scanValue(depth: Int): JsonValue {
            if (depth > MAXIMUM_DEPTH || index >= bytes.size) throw fail()
            val byte = at(index)
            return when {
                byte == OPEN_BRACE -> scanObject(depth + 1)
                byte == OPEN_BRACKET -> scanArray(depth + 1)
                byte == QUOTE -> JsonValue.Text(scanString())
                byte == 't'.code -> { literal("true"); JsonValue.Bool(true) }
                byte == 'f'.code -> { literal("false"); JsonValue.Bool(false) }
                byte == 'n'.code -> { literal("null"); JsonValue.Null }
                byte == MINUS || byte in ZERO..NINE -> JsonValue.Num(scanNumber())
                else -> throw fail()
            }
        }

        private fun scanObject(depth: Int): JsonValue.Obj {
            index += 1
            skipWhitespace()
            val members = LinkedHashMap<String, JsonValue>()
            if (consume(CLOSE_BRACE)) return JsonValue.Obj(members)
            while (true) {
                if (index >= bytes.size || at(index) != QUOTE) throw fail()
                val key = scanString()
                // The rule this whole scanner exists for.
                if (members.containsKey(key)) throw fail()
                skipWhitespace()
                if (!consume(COLON)) throw fail()
                skipWhitespace()
                members[key] = scanValue(depth)
                skipWhitespace()
                if (consume(CLOSE_BRACE)) return JsonValue.Obj(members)
                if (!consume(COMMA)) throw fail()
                skipWhitespace()
            }
        }

        private fun scanArray(depth: Int): JsonValue.Arr {
            index += 1
            skipWhitespace()
            val elements = ArrayList<JsonValue>()
            if (consume(CLOSE_BRACKET)) return JsonValue.Arr(elements)
            while (true) {
                elements.add(scanValue(depth))
                skipWhitespace()
                if (consume(CLOSE_BRACKET)) return JsonValue.Arr(elements)
                if (!consume(COMMA)) throw fail()
                skipWhitespace()
            }
        }

        private fun scanString(): String {
            index += 1
            val out = StringBuilder()
            val pending = ByteArrayOutputStream()
            while (index < bytes.size) {
                val byte = at(index)
                when {
                    byte == QUOTE -> {
                        index += 1
                        flush(pending, out)
                        return out.toString()
                    }
                    byte == BACKSLASH -> {
                        flush(pending, out)
                        index += 1
                        if (index >= bytes.size) throw fail()
                        when (at(index)) {
                            QUOTE -> out.append('"')
                            BACKSLASH -> out.append('\\')
                            '/'.code -> out.append('/')
                            'b'.code -> out.append('\b')
                            'f'.code -> out.append('\u000C')
                            'n'.code -> out.append('\n')
                            'r'.code -> out.append('\r')
                            't'.code -> out.append('\t')
                            'u'.code -> {
                                if (index + 4 >= bytes.size) throw fail()
                                var unit = 0
                                for (offset in 1..4) {
                                    unit = unit * 16 + (hexValue(at(index + offset)) ?: throw fail())
                                }
                                index += 4
                                out.append(unit.toChar())
                            }
                            else -> throw fail()
                        }
                        index += 1
                    }
                    // A raw control character inside a string is invalid JSON. It
                    // must arrive escaped or not at all.
                    byte < 0x20 -> throw fail()
                    else -> {
                        pending.write(byte)
                        index += 1
                    }
                }
            }
            throw fail()
        }

        /**
         * Decodes a literal run as UTF-8, refusing malformed input rather than
         * substituting U+FFFD. A package is identified by its bytes; silently
         * replacing an undecodable one changes what was hashed.
         */
        private fun flush(pending: ByteArrayOutputStream, out: StringBuilder) {
            if (pending.size() == 0) return
            val decoder = Charsets.UTF_8.newDecoder()
                .onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT)
            try {
                out.append(decoder.decode(ByteBuffer.wrap(pending.toByteArray())))
            } catch (_: CharacterCodingException) {
                throw fail()
            }
            pending.reset()
        }

        private fun scanNumber(): String {
            val start = index
            if (consume(MINUS) && index == bytes.size) throw fail()
            if (consume(ZERO)) {
                // A leading zero is not a number with a redundant digit; it is a
                // different grammar, and accepting it admits values a reader would
                // misread as octal.
                if (index < bytes.size && at(index) in ZERO..NINE) throw fail()
            } else if (!consumeDigits()) {
                throw fail()
            }
            if (consume(PERIOD) && !consumeDigits()) throw fail()
            if (index < bytes.size && (at(index) == 'e'.code || at(index) == 'E'.code)) {
                index += 1
                if (index < bytes.size && (at(index) == PLUS || at(index) == MINUS)) index += 1
                if (!consumeDigits()) throw fail()
            }
            if (index <= start) throw fail()
            return String(bytes, start, index - start, Charsets.US_ASCII)
        }

        private fun literal(value: String) {
            val expected = value.toByteArray(Charsets.US_ASCII)
            if (index + expected.size > bytes.size) throw fail()
            for (offset in expected.indices) {
                if (bytes[index + offset] != expected[offset]) throw fail()
            }
            index += expected.size
        }

        private fun consumeDigits(): Boolean {
            val start = index
            while (index < bytes.size && at(index) in ZERO..NINE) index += 1
            return index > start
        }

        private fun skipWhitespace() {
            while (index < bytes.size) {
                when (at(index)) {
                    0x20, 0x09, 0x0A, 0x0D -> index += 1
                    else -> return
                }
            }
        }

        private fun consume(code: Int): Boolean {
            if (index < bytes.size && at(index) == code) {
                index += 1
                return true
            }
            return false
        }

        private fun hexValue(code: Int): Int? = when (code) {
            in '0'.code..'9'.code -> code - '0'.code
            in 'a'.code..'f'.code -> code - 'a'.code + 10
            in 'A'.code..'F'.code -> code - 'A'.code + 10
            else -> null
        }

        private fun fail() =
            CharacterPackageImportException(CharacterPackageImportCode.INVALID_MANIFEST, phase)
    }
}
