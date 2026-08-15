#!/usr/bin/env python3
"""Generate Contracts/conformance/zip-profile.json.

The restricted ZIP profile is where hostile input actually arrives: a character
package is an archive a user chose, and everything downstream — staging, hashing,
sealing — trusts that this layer already refused the traversals, the links, the
overlapping ranges and the profiles nobody implemented. DEC-011 states the
policy; until now the only executable form of it was Swift.

Archives are built here by hand rather than with `zipfile`, because the subject
is byte-level policy and a convenience writer decides too many of the fields for
you. Every header value in a case is one this file chose.

Usage:  python3 Tools/make_zip_corpus.py [--check]
"""

from __future__ import annotations

import argparse
import base64
import json
import struct
import sys
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "Contracts/conformance/zip-profile.json"

LOCAL_SIG = 0x04034B50
CENTRAL_SIG = 0x02014B50
EOCD_SIG = 0x06054B50

STORED, DEFLATED = 0, 8
UTF8_FLAG = 0x0800

# Unix host, regular file, rw-r--r--. The profile refuses any execute bit and
# anything that is not a plain file or a plain directory.
UNIX_HOST = 3 << 8
REGULAR = 0o100644 << 16
DIRECTORY = 0o040755 << 16
SYMLINK = 0o120777 << 16
EXECUTABLE = 0o100755 << 16


class Entry:
    def __init__(
        self,
        name: str,
        data: bytes = b"",
        *,
        method: int = STORED,
        flags: int | None = None,
        made_by: int = UNIX_HOST | 20,
        external: int | None = None,
        needed: int = 20,
        extra: bytes = b"",
        local_extra: bytes | None = None,
        disk_start: int = 0,
        crc_override: int | None = None,
        local_crc_override: int | None = None,
        local_sizes_zero: bool = False,
        name_bytes: bytes | None = None,
    ):
        self.name = name
        self.name_bytes = name_bytes if name_bytes is not None else name.encode("utf-8")
        self.data = data
        self.method = method
        self.is_dir = name.endswith("/")
        self.flags = flags if flags is not None else (UTF8_FLAG if not self.name_bytes.isascii() else 0)
        self.made_by = made_by
        self.external = external if external is not None else (DIRECTORY if self.is_dir else REGULAR)
        self.needed = needed
        self.extra = extra
        self.local_extra = extra if local_extra is None else local_extra
        self.disk_start = disk_start
        self.crc_override = crc_override
        self.local_crc_override = local_crc_override
        self.local_sizes_zero = local_sizes_zero

    @property
    def payload(self) -> bytes:
        if self.method == DEFLATED:
            return zlib.compress(self.data, 9)[2:-4]  # raw deflate
        return self.data

    @property
    def crc(self) -> int:
        return zlib.crc32(self.data) & 0xFFFFFFFF


def build(entries: list[Entry], *, comment: bytes = b"", eocd_overrides: dict | None = None,
          trailing: bytes = b"") -> bytes:
    out = bytearray()
    placements = []
    for e in entries:
        offset = len(out)
        payload = e.payload
        local_crc = e.local_crc_override if e.local_crc_override is not None else e.crc
        local_comp = 0 if e.local_sizes_zero else len(payload)
        local_uncomp = 0 if e.local_sizes_zero else len(e.data)
        out += struct.pack(
            "<IHHHHHIIIHH",
            LOCAL_SIG, e.needed, e.flags, e.method, 0, 0,
            local_crc, local_comp, local_uncomp,
            len(e.name_bytes), len(e.local_extra),
        )
        out += e.name_bytes + e.local_extra + payload
        placements.append((e, offset, len(payload)))

    central_offset = len(out)
    for e, offset, compressed in placements:
        crc = e.crc_override if e.crc_override is not None else e.crc
        out += struct.pack(
            "<IHHHHHHIIIHHHHHII",
            CENTRAL_SIG, e.made_by, e.needed, e.flags, e.method, 0, 0,
            crc, compressed, len(e.data),
            len(e.name_bytes), len(e.extra), 0, e.disk_start, 0,
            e.external, offset,
        )
        out += e.name_bytes + e.extra
    central_size = len(out) - central_offset

    fields = {
        "disk": 0, "central_disk": 0,
        "disk_entries": len(entries), "total_entries": len(entries),
        "central_size": central_size, "central_offset": central_offset,
        "comment_length": len(comment),
    }
    fields.update(eocd_overrides or {})
    out += struct.pack(
        "<IHHHHIIH",
        EOCD_SIG, fields["disk"], fields["central_disk"],
        fields["disk_entries"], fields["total_entries"],
        fields["central_size"], fields["central_offset"], fields["comment_length"],
    )
    out += comment + trailing
    return bytes(out)


def simple(name: str = "manifest.json", data: bytes = b'{"schema":"joi.character.v1"}') -> Entry:
    return Entry(name, data)


# (id, expect, note, archive bytes). `expect` is "accept" or a stable code.
def cases() -> list[dict]:
    out: list[dict] = []

    def add(case_id, expect, note, payload, *, normative=True, current=None, finding=None):
        case = {"id": case_id, "expect": expect, "note": note, "payload": payload}
        if not normative:
            case.update(normative=False, currentOutcome=current, finding=finding)
        out.append(case)

    # --- accepted -----------------------------------------------------------
    add("stored-single", "accept",
        "One stored entry. The baseline every rejection below is a mutation of.",
        build([simple()]))
    add("deflated-single", "accept",
        "Deflate is the only compression method admitted besides stored.",
        build([Entry("manifest.json", bytes(range(256)) * 2, method=DEFLATED, flags=0x0002)]))
    add("directory-entry", "accept",
        "A directory entry carries no data and is not reported as a file.",
        build([Entry("motions/", b"", external=DIRECTORY), simple("motions/idle.vrma", b"clip")]))
    add("utf8-name", "accept",
        "A non-ASCII name is admitted when the UTF-8 flag is set and the bytes "
        "round-trip through UTF-8.",
        build([simple("资料/说明.json", b"{}")]))
    add("dos-host", "accept",
        "A DOS/NTFS-hosted archive is admitted; only its directory bit is checked, "
        "because DOS attributes carry no permission model to check.",
        build([Entry("manifest.json", b"{}", made_by=20, external=0x20)]))

    # --- unsupportedArchiveProfile: safe, but outside the profile -----------
    add("zip64-end-record", "unsupportedArchiveProfile",
        "A ZIP64 end record anywhere in the tail. Refused by signature before "
        "parsing, because ZIP64 changes the meaning of fields this parser reads.",
        build([simple()], trailing=b"PK\x06\x06" + b"\x00" * 8))
    add("zip64-locator", "unsupportedArchiveProfile",
        "The ZIP64 locator signature, likewise.",
        build([simple()], trailing=b"PK\x06\x07" + b"\x00" * 8))
    add("encrypted-entry", "unsupportedArchiveProfile",
        "Flag bit 0 is traditional encryption. The bytes may be perfectly well "
        "formed; nothing here can read them.",
        build([Entry("manifest.json", b"{}", flags=0x0001)]))
    add("strong-encryption", "unsupportedArchiveProfile",
        "Flag bit 6 is strong encryption.",
        build([Entry("manifest.json", b"{}", flags=0x0040)]))
    add("data-descriptor-placeholder-local", "accept",
        "Flag bit 3 says the writer streamed, so the local header holds zeros and "
        "the real values trail the payload. Admitted (DEC-029) because Finder sets "
        "it on every entry; the central directory stays authoritative.",
        build([Entry("manifest.json", b"{}", flags=0x0008,
                     local_crc_override=0, local_sizes_zero=True)]))
    add("data-descriptor-filled-local", "accept",
        "The same flag with the local header filled in anyway, which some writers "
        "do. Either form is admitted; nothing between them is.",
        build([Entry("manifest.json", b"{}", flags=0x0008)]))
    add("data-descriptor-local-disagrees", "malformedArchive",
        "Flag bit 3 with a local header that is neither the placeholder nor the "
        "truth. Two readers would disagree about this entry's size, which is the "
        "ambiguity the flag is not permission to introduce.",
        build([Entry("manifest.json", b"{}", flags=0x0008, local_crc_override=0xDEADBEEF)]))
    add("unsupported-method", "unsupportedArchiveProfile",
        "bzip2. Refused as unsupported rather than corrupt: the archive is fine, "
        "this reader is not.",
        build([Entry("manifest.json", b"{}", method=12)]))
    add("needs-version-45", "unsupportedArchiveProfile",
        "Extract-version 45 declares ZIP64 regardless of what the fields hold.",
        build([Entry("manifest.json", b"{}", needed=45)]))
    add("multidisk", "unsupportedArchiveProfile",
        "A split archive. One volume cannot be validated on its own.",
        build([simple()], eocd_overrides={"disk": 1, "central_disk": 1}))
    add("entry-on-other-disk", "unsupportedArchiveProfile",
        "A central entry pointing at another volume.",
        build([Entry("manifest.json", b"{}", disk_start=1)]))
    add("zip64-extra-field", "unsupportedArchiveProfile",
        "Extra field 0x0001 is the ZIP64 extension.",
        build([Entry("manifest.json", b"{}", extra=struct.pack("<HH", 0x0001, 0))]))
    add("unknown-extra-field", "unsupportedArchiveProfile",
        "Unknown extra fields are refused rather than skipped: an extra field is "
        "where a link target or an alternate size would hide.",
        build([Entry("manifest.json", b"{}", extra=struct.pack("<HH", 0x9901, 2) + b"\x00\x00")]))
    add("unknown-host", "unsupportedArchiveProfile",
        "A host system whose attribute encoding this parser does not know, so its "
        "file-type and permission bits cannot be checked.",
        build([Entry("manifest.json", b"{}", made_by=(7 << 8) | 20)]))
    add("unexpected-flag-bit", "unsupportedArchiveProfile",
        "A stored entry setting a deflate-only compression-option bit.",
        build([Entry("manifest.json", b"{}", flags=0x0004)]))

    # --- unsafeArchive: the archive is trying something -----------------------
    add("path-traversal", "unsafeArchive",
        "The oldest one. `..` is refused as a path component, not sanitized away.",
        build([simple("../escape.txt", b"x")]))
    add("absolute-path", "unsafeArchive",
        "A leading slash.",
        build([simple("/etc/passwd", b"x")]))
    add("backslash-path", "unsafeArchive",
        "A backslash is refused outright rather than translated, because which "
        "platform reads it as a separator is not this layer's guess to make.",
        build([simple("a\\b.txt", b"x")]))
    add("drive-letter", "unsafeArchive",
        "A colon, which is a drive separator on one platform and a legal name "
        "character on another.",
        build([simple("C:data.txt", b"x")]))
    add("control-character-name", "unsafeArchive",
        "A newline in a name. Nothing legitimate needs one, and log lines and "
        "path displays are where it would show up.",
        build([simple("bad\nname.txt", b"x")]))
    add("empty-path-component", "unsafeArchive",
        "A doubled separator. The empty component has no meaning to resolve.",
        build([simple("a//b.txt", b"x")]))
    add("dot-component", "unsafeArchive",
        "A single-dot component.",
        build([simple("a/./b.txt", b"x")]))
    add("case-collision", "unsafeArchive",
        "Two names differing only by case. On a case-insensitive volume the "
        "second silently becomes the first, after the manifest has accounted for "
        "two files.",
        build([simple("Model.vrm", b"a"), simple("model.vrm", b"b")]))
    add("normalization-collision", "unsafeArchive",
        "The same name composed and decomposed. Byte-distinct, filesystem-identical.",
        build([simple("café.txt", b"a"), simple("café.txt", b"b")]))
    add("symlink-entry", "unsafeArchive",
        "A symbolic link. An installed tree that can point outside itself is not "
        "sealed content.",
        build([Entry("link", b"../../etc/passwd", external=SYMLINK)]))
    add("executable-entry", "unsafeArchive",
        "An execute bit. A character package is art, and nothing in it runs.",
        build([Entry("run.sh", b"#!/bin/sh\n", external=EXECUTABLE)]))
    add("directory-with-payload", "unsafeArchive",
        "An entry marked as a directory that also carries bytes.",
        build([Entry("motions/", b"payload", external=DIRECTORY)]))
    add("non-utf8-name", "unsafeArchive",
        "A name that is not valid UTF-8. There is no encoding to fall back to "
        "that would not be a guess.",
        build([Entry("bad.txt", b"x", name_bytes=b"bad\xff.txt")]))
    add("central-names-a-different-file", "malformedArchive",
        "Two central entries pointing at one local header, the second under a "
        "different name. The local header still carries the first name, and "
        "local-central disagreement is caught before the shared range is: two "
        "readers would disagree about what this entry is called.",
        _overlapping())
    add("expansion-ratio", "unsafeArchive",
        "A zip bomb in miniature: highly compressible payload past the 20:1 "
        "expansion bound.",
        build([Entry("bomb.bin", b"\x00" * 2_000_000, method=DEFLATED, flags=0x0002)]))

    # --- malformedArchive: the bytes do not describe an archive --------------
    add("too-short", "malformedArchive",
        "Shorter than an end-of-central-directory record.",
        b"PK\x05\x06")
    add("no-eocd", "malformedArchive",
        "No end record at all.",
        b"PK\x03\x04" + b"\x00" * 64)
    add("comment-length-mismatch", "malformedArchive",
        "A declared comment length that does not reach the end of the file — the "
        "classic way to hide bytes after the archive a reader will not see.",
        build([simple()], eocd_overrides={"comment_length": 5}))
    add("central-offset-mismatch", "malformedArchive",
        "A central directory whose declared size does not land on the end record.",
        build([simple()], eocd_overrides={"central_size": 999}))
    add("bad-central-signature", "malformedArchive",
        "A corrupted central header signature.",
        _corrupt_central_signature())
    add("local-central-crc-mismatch", "malformedArchive",
        "Local and central headers disagreeing about the CRC. Which one a reader "
        "believes is exactly the ambiguity this profile removes.",
        build([Entry("manifest.json", b"{}", local_crc_override=0xDEADBEEF)]))
    add("entry-count-mismatch", "malformedArchive",
        "An end record claiming more entries than the central directory holds.",
        build([simple()], eocd_overrides={"disk_entries": 2, "total_entries": 2}))

    # --- what mainstream archivers actually emit ----------------------------
    #
    # Synthesised with the exact header fields each tool was measured writing on
    # 2026-08-15, so these stay reproducible while remaining faithful. Every one
    # is refused today, which is a product problem and not a security win: a user
    # who zips a Live2D folder by any ordinary means cannot import it.
    add("producer-usr-bin-zip", "accept",
        "What `zip -r` writes: an extended-timestamp field and a Unix UID/GID "
        "field, on every entry.",
        build([
            Entry("motions/", b"", external=DIRECTORY, extra=_ut() + _ux()),
            Entry("motions/idle.vrma", b"clip", extra=_ut() + _ux()),
            Entry("manifest.json", b"{}", extra=_ut() + _ux()),
        ]),
        )
    add("producer-ditto", "accept",
        "What macOS `ditto -c -k` — the engine behind Finder's Compress — writes: "
        "an old-style Unix field, plus a __MACOSX sidecar tree.",
        build([
            Entry("motions/", b"", external=DIRECTORY, extra=_old_ux()),
            Entry("motions/idle.vrma", b"clip", extra=_old_ux()),
            Entry("manifest.json", b"{}", extra=_old_ux()),
            Entry("__MACOSX/", b"", external=DIRECTORY, extra=_old_ux()),
            Entry("__MACOSX/._manifest.json", b"\x00\x05\x16\x07resource fork", extra=_old_ux()),
            Entry(".DS_Store", b"\x00\x00\x00\x01Bud1", extra=_old_ux()),
        ]),
        )
    add("producer-python-zipfile", "accept",
        "What Python's zipfile writes by default: an external attribute holding "
        "permission bits with no file-type bits at all.",
        build([Entry("manifest.json", b"{}", external=0o600 << 16)]),
        )

    return out


def _ut() -> bytes:
    """Extended timestamp, as Info-ZIP writes it."""
    return struct.pack("<HHB", 0x5455, 5, 0x03) + struct.pack("<I", 0)


def _ux() -> bytes:
    """Unix UID/GID (0x7875), as `zip` writes it."""
    return struct.pack("<HHBB", 0x7875, 11, 1, 4) + struct.pack("<I", 501) + struct.pack("<BI", 4, 20)


def _old_ux() -> bytes:
    """Old Info-ZIP Unix field (0x5855)."""
    return struct.pack("<HH", 0x5855, 12) + struct.pack("<IIHH", 0, 0, 501, 20)


def _overlapping() -> bytes:
    """Two central entries whose local ranges are the same bytes."""
    entry = simple("a.txt", b"payload")
    archive = bytearray(build([entry]))
    central_offset = struct.unpack("<I", archive[-6:-2])[0]
    central = bytes(archive[central_offset:-22])
    rebuilt = bytearray(archive[:central_offset])
    rebuilt += central
    second = bytearray(central)
    name_length = struct.unpack("<H", second[28:30])[0]
    second[46:46 + name_length] = b"b.txt"
    rebuilt += second
    size = len(rebuilt) - central_offset
    rebuilt += struct.pack("<IHHHHIIH", EOCD_SIG, 0, 0, 2, 2, size, central_offset, 0)
    return bytes(rebuilt)


def _corrupt_central_signature() -> bytes:
    archive = bytearray(build([simple()]))
    central_offset = struct.unpack("<I", archive[-6:-2])[0]
    archive[central_offset + 3] = 0x00
    return bytes(archive)


def build_document() -> dict:
    return {
        "schema": "joi.conformance.zip-profile.v1",
        "description": (
            "The restricted ZIP profile: what a character archive may be before "
            "anything is written to disk. Every case is a complete archive; feed "
            "its bytes to the preflight and compare the outcome."
        ),
        "notes": [
            "`expect` is `accept` or a stable import code. The three refusals are "
            "deliberately distinct: `unsupportedArchiveProfile` means the archive is "
            "well formed and this reader will not open it, `unsafeArchive` means the "
            "archive is attempting something, and `malformedArchive` means the bytes "
            "do not describe an archive. A user can act on the first, and should be "
            "told something different about the second.",
            "Archives are built by Tools/make_zip_corpus.py rather than by a ZIP "
            "library, because a convenience writer chooses header fields the policy "
            "is about.",
            "Limits are stated in the contract and not vectored: 128 MiB archive, "
            "128 MiB per file, 512 MiB expanded, 2000 entries. A case for the entry "
            "count alone would be 2001 headers of filler.",
        ],
        "cases": [
            {
                "id": c["id"],
                "expect": c["expect"],
                "note": c["note"],
                **({} if c.get("normative", True) else {
                    "normative": False,
                    "currentOutcome": c["currentOutcome"],
                    "finding": c["finding"],
                }),
                "archiveBase64": base64.b64encode(c["payload"]).decode("ascii"),
            }
            for c in cases()
        ],
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="fail if the file on disk is stale")
    args = parser.parse_args()

    generated = json.dumps(build_document(), indent=2, ensure_ascii=False) + "\n"
    if args.check:
        current = OUTPUT.read_text(encoding="utf-8") if OUTPUT.exists() else ""
        if current != generated:
            print(f"{OUTPUT.relative_to(ROOT)} is stale; re-run without --check", file=sys.stderr)
            return 1
        print(f"{OUTPUT.relative_to(ROOT)} is current")
        return 0

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(generated, encoding="utf-8")
    print(f"wrote {OUTPUT.relative_to(ROOT)} with {len(cases())} cases")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
