package com.joi.mobile.character

import java.io.File

/**
 * Reads `Contracts/conformance/` — the same files the Swift suite runs.
 *
 * Parsed with Joi's own strict scanner rather than a test-only JSON library. If
 * the scanner cannot read the corpus, the corpus does not get read, which is a
 * more useful failure than a second parser papering over a first one.
 */
object Corpus {
    private const val MAXIMUM_BYTES = 4 * 1024 * 1024

    val directory: File by lazy {
        var candidate: File? = File("").absoluteFile
        while (candidate != null) {
            val conformance = File(candidate, "Contracts/conformance")
            if (conformance.isDirectory) return@lazy conformance
            candidate = candidate.parentFile
        }
        error("Contracts/conformance not found above ${File("").absolutePath}")
    }

    fun load(name: String): JsonValue.Obj =
        StrictJson.objectOf(File(directory, name).readBytes(), MAXIMUM_BYTES)

    fun cases(name: String): List<JsonValue.Obj> =
        (load(name).members["cases"] as JsonValue.Arr).elements.map { it as JsonValue.Obj }
}

fun JsonValue.Obj.text(key: String): String = (members[key] as JsonValue.Text).value

fun JsonValue.Obj.optionalText(key: String): String? = (members[key] as? JsonValue.Text)?.value

fun JsonValue.Obj.bool(key: String): Boolean? = (members[key] as? JsonValue.Bool)?.value

fun JsonValue.Obj.list(key: String): List<JsonValue> = (members[key] as JsonValue.Arr).elements

fun JsonValue.Obj.optionalList(key: String): List<JsonValue>? = (members[key] as? JsonValue.Arr)?.elements

fun JsonValue.Obj.strings(key: String): List<String> = list(key).map { (it as JsonValue.Text).value }
