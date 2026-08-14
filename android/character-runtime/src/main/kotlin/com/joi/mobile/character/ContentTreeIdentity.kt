package com.joi.mobile.character

import java.io.File
import java.security.MessageDigest
import java.text.Normalizer

/**
 * What a character package *is*, reduced to one string.
 *
 * A package's identity is derived from its sealed content, not from anything it
 * claims about itself, so two imports of the same bytes install once and a
 * mutated tree stops matching the installation that references it.
 *
 * The rule, stated in full in `Contracts/conformance/README.md`:
 *
 * ```
 * frame(data) := uint64_be(len(data)) || data
 *
 * H = SHA256()
 * H << frame("joi.character.content-tree.v1")
 * for path in sorted(paths):                    # by UTF-8 bytes
 *     H << frame(utf8(path))
 *     H << uint64_be(byte_length_of_file)
 *     H << frame(utf8(lowercase_hex_sha256(file_bytes)))
 * contentID = "sha256:" || lowercase_hex(H)
 * ```
 *
 * Three details are easy to get subtly wrong, and each produces a different
 * identity for byte-identical content:
 *
 *  - the per-file digest enters as its **64 characters of hex text**, not as its
 *    32 raw bytes;
 *  - ordering is over the whole relative path as **UTF-8 bytes**. Kotlin's
 *    default `sorted()` orders by UTF-16 code units, which disagrees whenever a
 *    supplementary-plane character meets one in U+E000–U+FFFF;
 *  - every field is length-framed, so no combination of paths and digests can be
 *    reinterpreted as a different tree.
 *
 * `Contracts/conformance/content-id.json` has a vector for each.
 */
object ContentTreeIdentity {
    private const val DOMAIN = "joi.character.content-tree.v1"
    private const val PREFIX = "sha256:"

    /** One file's contribution: where it sits and what it contains. */
    data class Entry(val path: String, val sizeBytes: Long, val sha256Hex: String)

    /**
     * Orders two package-relative paths the way the contract does: by unsigned
     * UTF-8 bytes.
     */
    val pathOrder: Comparator<String> = Comparator { left, right ->
        val a = left.toByteArray(Charsets.UTF_8)
        val b = right.toByteArray(Charsets.UTF_8)
        var index = 0
        while (index < a.size && index < b.size) {
            val difference = (a[index].toInt() and 0xFF) - (b[index].toInt() and 0xFF)
            if (difference != 0) return@Comparator difference
            index += 1
        }
        a.size - b.size
    }

    fun of(entries: List<Entry>): String {
        val digest = MessageDigest.getInstance("SHA-256")
        digest.frame(DOMAIN.toByteArray(Charsets.UTF_8))
        for (entry in entries.sortedWith(compareBy(pathOrder) { it.path })) {
            digest.frame(entry.path.toByteArray(Charsets.UTF_8))
            digest.update(bigEndian(entry.sizeBytes))
            digest.frame(entry.sha256Hex.toByteArray(Charsets.UTF_8))
        }
        return PREFIX + digest.digest().toHex()
    }

    /**
     * Computes the identity of an unpacked tree.
     *
     * Paths are normalized to NFC before hashing. That is not cosmetic: Darwin
     * hands back a decomposed name for a file written composed, so an identity
     * taken over whatever the filesystem returned would be a property of the
     * volume rather than of the package, and the same `.joi-character` would
     * install under two different identities on two platforms.
     */
    fun ofDirectory(root: File): String = of(entriesOf(root))

    fun entriesOf(root: File): List<Entry> {
        require(root.isDirectory) { "content root must be a directory" }
        val rootPath = root.canonicalFile
        val entries = ArrayList<Entry>()
        collect(rootPath, rootPath, entries)
        return entries
    }

    private fun collect(root: File, current: File, into: MutableList<Entry>) {
        val children = current.listFiles() ?: throw CharacterPackageImportException(
            CharacterPackageImportCode.UNSAFE_ARCHIVE,
            CharacterPackageImportPhase.SEAL,
        )
        for (child in children) {
            // A symbolic link inside sealed content is refused, not followed: an
            // installed tree that can point outside itself is not sealed.
            if (!child.canonicalFile.startsWith(root)) {
                throw CharacterPackageImportException(
                    CharacterPackageImportCode.UNSAFE_ARCHIVE,
                    CharacterPackageImportPhase.SEAL,
                )
            }
            when {
                child.isDirectory -> collect(root, child, into)
                child.isFile -> {
                    val relative = child.canonicalPath.removePrefix(root.path + File.separator)
                    into.add(
                        Entry(
                            path = Normalizer.normalize(relative.replace(File.separatorChar, '/'), Normalizer.Form.NFC),
                            sizeBytes = child.length(),
                            sha256Hex = sha256OfFile(child),
                        )
                    )
                }
                else -> throw CharacterPackageImportException(
                    CharacterPackageImportCode.UNSAFE_ARCHIVE,
                    CharacterPackageImportPhase.SEAL,
                )
            }
        }
    }

    fun sha256Of(bytes: ByteArray): String =
        MessageDigest.getInstance("SHA-256").digest(bytes).toHex()

    fun sha256OfFile(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        val buffer = ByteArray(64 * 1024)
        file.inputStream().use { stream ->
            while (true) {
                val read = stream.read(buffer)
                if (read <= 0) break
                digest.update(buffer, 0, read)
            }
        }
        return digest.digest().toHex()
    }

    private fun MessageDigest.frame(payload: ByteArray) {
        update(bigEndian(payload.size.toLong()))
        update(payload)
    }

    private fun bigEndian(value: Long): ByteArray {
        val out = ByteArray(8)
        for (index in 0 until 8) {
            out[index] = ((value ushr (8 * (7 - index))) and 0xFF).toByte()
        }
        return out
    }

    private fun ByteArray.toHex(): String {
        val out = StringBuilder(size * 2)
        for (byte in this) {
            val value = byte.toInt() and 0xFF
            out.append("0123456789abcdef"[value ushr 4])
            out.append("0123456789abcdef"[value and 0x0F])
        }
        return out.toString()
    }
}
