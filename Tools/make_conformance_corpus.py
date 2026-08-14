#!/usr/bin/env python3
"""Generate the content-tree identity vectors in Contracts/conformance/.

The other conformance files are hand-authored, because their expected values are
stable error codes and payload strings that a human should be able to read and
argue with. Content identity is different: its expected values are digests, so
they have to be computed, and computing them here — from the written rule rather
than from either shipping implementation — is what makes the vectors a
specification instead of a recording of current behaviour.

The rule (see Contracts/conformance/README.md):

    frame(data) := uint64_be(len(data)) || data

    H = SHA256()
    H << frame("joi.character.content-tree.v1")
    for path in sorted(paths):                       # by UTF-8 bytes
        H << frame(utf8(path))
        H << uint64_be(byte_length_of_file)
        H << frame(utf8(lowercase_hex_sha256_of_file_bytes)))
    contentID = "sha256:" || lowercase_hex(H)

Note the file digest enters as its 64-character hex *text*, not as its 32 raw
bytes. That is not an aesthetic choice on this side — it is what the shipping
iOS implementation does, and an Android port that frames raw bytes would produce
a different identity for byte-identical content.

Usage:  python3 Tools/make_conformance_corpus.py [--check]
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "Contracts/conformance/content-id.json"

DOMAIN = b"joi.character.content-tree.v1"


def frame(payload: bytes) -> bytes:
    return struct.pack(">Q", len(payload)) + payload


def content_id(files: dict[str, bytes]) -> str:
    hasher = hashlib.sha256()
    hasher.update(frame(DOMAIN))
    for path in sorted(files, key=lambda name: name.encode("utf-8")):
        body = files[path]
        hasher.update(frame(path.encode("utf-8")))
        hasher.update(struct.pack(">Q", len(body)))
        hasher.update(frame(hashlib.sha256(body).hexdigest().encode("utf-8")))
    return "sha256:" + hasher.hexdigest()


# Each case is (id, note, {path: bytes}) and is normative unless it appears in
# PENDING below. Keep payloads small: these files are read by two test suites on
# every run, and nothing here is testing throughput.
CASES: list[tuple[str, str, dict[str, bytes]]] = [
    (
        "empty-tree",
        "No files at all. Only the domain frame is hashed, so an empty tree still "
        "has a stable identity rather than a degenerate one.",
        {},
    ),
    (
        "single-file",
        "One file. Pins path framing, size framing and hex-text digest framing "
        "against each other.",
        {"manifest.json": b'{"schema":"joi.character.v1"}'},
    ),
    (
        "empty-file",
        "A zero-byte file still contributes its path, a zero size and the SHA-256 "
        "of the empty string. A port that skips empty files diverges here.",
        {"manifest.json": b"{}", "empty.bin": b""},
    ),
    (
        "binary-payload",
        "Non-UTF-8 bytes, including a NUL and a 0xFF. Digests are over raw bytes, "
        "never over a decoded string.",
        {
            "manifest.json": b"{}",
            "model.vrm": bytes([0x67, 0x6C, 0x54, 0x46, 0x02, 0x00, 0x00, 0xFF]),
        },
    ),
    (
        "nested-paths",
        "Package-relative paths with a directory segment. Ordering is over the "
        "whole relative path, so 'model.vrm' sorts before 'motions/greet.vrma' "
        "('d' < 't'), not after it by directory depth.",
        {
            "manifest.json": b"{}",
            "model.vrm": b"model",
            "motions/greet.vrma": b"greet",
            "motions/idle.vrma": b"idle",
        },
    ),
    (
        "order-independence",
        "Same content as 'nested-paths' with the entries authored in reverse. The "
        "identity must be identical: a port that hashes in enumeration order "
        "rather than sorted order passes 'nested-paths' and fails this one.",
        {
            "motions/idle.vrma": b"idle",
            "motions/greet.vrma": b"greet",
            "model.vrm": b"model",
            "manifest.json": b"{}",
        },
    ),
    (
        "separator-ordering",
        "'/' is 0x2F, below every alphanumeric, so 'a/b' sorts before 'ab'. This "
        "is the case where a sort over path *components* diverges from a sort "
        "over the path string.",
        {"a/b": b"1", "ab": b"2", "a-b": b"3"},
    ),
    (
        "same-bytes-different-paths",
        "Two files with identical content. Identity must still separate them, "
        "which it does only because the path is framed alongside the digest.",
        {"one.txt": b"same", "two.txt": b"same"},
    ),
    (
        "non-ascii-paths",
        "CJK path segments, none of which has a canonical decomposition. Ordering "
        "is by UTF-8 bytes, not by a locale collation, so 'zzz.txt' sorts before "
        "'资料/说明.json'.",
        {
            "manifest.json": b"{}",
            "资料/说明.json": b"{}",
            "zzz.txt": b"z",
        },
    ),
    (
        "supplementary-plane-ordering",
        "U+FF21 (UTF-8 EF BC A1, UTF-16 FF21) against U+1F38F (UTF-8 F0 9F 8E 8F, "
        "UTF-16 D83C DF8F). By UTF-8 bytes the fullwidth letter sorts first; by "
        "UTF-16 code units the emoji does. Java and Kotlin's default String "
        "ordering is UTF-16, so a port that calls sorted() and stops fails exactly "
        "here and nowhere else in this file.",
        {
            "manifest.json": b"{}",
            "Ａ.txt": b"fullwidth",
            "🎏.txt": b"carp",
        },
    ),
]

# Cases that are written from the rule but that the shipping iOS implementation
# does not currently satisfy. They are carried in the corpus, and marked, rather
# than deleted: deleting one would erase the finding, and asserting on one would
# stop the lane on a question that belongs to a decision, not to a test.
#
# See docs/DECISIONS.md DEC-026.
PENDING: dict[str, str] = {
    "decomposable-path": (
        "The path is hashed as the bytes the filesystem hands back, not as the "
        "bytes the package declared. Darwin returns 'café.txt' decomposed "
        "(U+0065 U+0301) even when it was written composed (U+00E9), so iOS "
        "computes this identity over NFD bytes while a port on ext4 computes it "
        "over NFC bytes. The two never agree, and no test caught it because "
        "Swift's String equality is canonical: the installer's "
        "`normalized == path` guard compares NFC against NFD and returns true. "
        "The rule as written here — hash NFC bytes — is the one that makes "
        "identity a property of the package rather than of the volume."
    ),
}

CASES.append(
    (
        "decomposable-path",
        "A filename with a canonical decomposition, written composed. Every "
        "European accented name and several kana with dakuten land here.",
        {"manifest.json": b"{}", "café.txt": b"cafe"},
    )
)


def build() -> dict:
    return {
        "schema": "joi.conformance.content-id.v1",
        "description": (
            "Content-tree identity vectors. Both the iOS and the Android package "
            "installer must produce the listed contentID for the listed files."
        ),
        "domainSeparator": DOMAIN.decode("ascii"),
        "pathNormalization": (
            "Paths are hashed as NFC UTF-8 bytes. Normalization is a property of "
            "the package, never of the volume it was unpacked onto."
        ),
        "cases": [
            case
            for case in (
                {
                    "id": case_id,
                    "note": note,
                    **({"normative": False, "finding": PENDING[case_id]} if case_id in PENDING else {}),
                    "files": [
                        {"path": path, "base64": base64.b64encode(body).decode("ascii")}
                        for path, body in sorted(files.items(), key=lambda kv: kv[0].encode("utf-8"))
                    ],
                    "contentID": content_id(files),
                }
                for case_id, note, files in CASES
            )
        ],
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="fail if the file on disk is stale")
    args = parser.parse_args()

    generated = json.dumps(build(), indent=2, ensure_ascii=False) + "\n"
    if args.check:
        current = OUTPUT.read_text(encoding="utf-8") if OUTPUT.exists() else ""
        if current != generated:
            print(f"{OUTPUT.relative_to(ROOT)} is stale; re-run without --check", file=sys.stderr)
            return 1
        print(f"{OUTPUT.relative_to(ROOT)} is current")
        return 0

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(generated, encoding="utf-8")
    print(f"wrote {OUTPUT.relative_to(ROOT)} with {len(CASES)} cases")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
