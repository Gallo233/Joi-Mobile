#!/usr/bin/env python3
"""Builds a canonical `.joi-character` package from a local model.

This exists so the real import → install → activate → render path can be tested
with real models. A bare `.vrm` or Live2D `.zip` installs but stays quarantined
as `rightsUnverified`, which is correct: those formats carry no provenance, so
nothing can assert who authored the model or under what licence. A canonical
package does carry it, which is why this tool *requires* an author and a licence
rather than defaulting them - declaring provenance is the whole point, and a tool
that invented it would be laundering the rights question rather than answering
it.

    Tools/make_character_package.py \
        --input ~/models/hiyori --renderer live2d \
        --entry hiyori_pro_t11.model3.json \
        --name 桃瀬ひより --author "Live2D Inc." \
        --license "Live2D Free Material License; local evaluation only" \
        --out ~/packages/hiyori.joi-character

Nothing this produces may be redistributed unless the declared licence permits
it. The output is a local test artefact.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
import zipfile
from pathlib import Path

# Mirrors CharacterMediaValidator.mediaType(for:). An extension missing here is
# rejected by the installer, so an unknown file must fail loudly at packaging
# time rather than produce a package that cannot install.
MEDIA_TYPES = {
    ".vrm": "model/gltf-binary",
    ".vrma": "model/gltf-binary",
    ".png": "image/png",
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".webp": "image/webp",
    ".wav": "audio/wav",
    ".mp3": "audio/mpeg",
    ".m4a": "audio/mp4",
    ".ogg": "audio/ogg",
    ".moc3": "application/vnd.live2d.moc3",
    ".json": "application/json",
}

MAXIMUM_FILES = 2000
MAXIMUM_EXPANDED_BYTES = 512 * 1024 * 1024


def media_type(path: Path) -> str:
    suffix = path.suffix.lower()
    if suffix not in MEDIA_TYPES:
        raise SystemExit(
            f"error: {path.name} has extension '{suffix}', which the installer "
            "cannot classify and would reject. Remove it or convert it."
        )
    return MEDIA_TYPES[suffix]


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def collect(root: Path) -> list[tuple[str, Path]]:
    entries: list[tuple[str, Path]] = []
    for path in sorted(root.rglob("*")):
        if not path.is_file() or path.name.startswith("."):
            continue
        if path.is_symlink():
            raise SystemExit(f"error: {path} is a symbolic link; the installer rejects those")
        entries.append((path.relative_to(root).as_posix(), path))
    return entries


# Every entry is written as a plain regular file, mode 0644, with a fixed
# timestamp. The installer's restricted profile requires Unix entries to carry
# regular-file type bits and no execute bits, and `writestr` would otherwise
# emit an entry with no type bits at all, which is rejected at preflight.
FIXED_TIMESTAMP = (2026, 1, 1, 0, 0, 0)
REGULAR_FILE_0644 = (0o100644 << 16)


IDENTIFIER_ALLOWED = set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")


def _valid_identifier(value: str) -> bool:
    """Mirrors the installer's rule: ASCII only, starting alphanumeric."""
    return (
        bool(value)
        and len(value) <= 160
        and value[0].isascii()
        and value[0].isalnum()
        and all(c in IDENTIFIER_ALLOWED for c in value)
    )


def _derive_id(name: str) -> str:
    """Derives an ASCII id from a display name.

    A CJK name has no usable ASCII, and `str.isalnum()` is true for CJK, so a
    naive slug produces a non-ASCII id that the installer rejects. Such names
    fall back to a digest of the name, which is stable across runs.
    """
    slug = "".join(c if (c.isascii() and c.isalnum()) else "-" for c in name.lower()).strip("-")
    while "--" in slug:
        slug = slug.replace("--", "-")
    if not slug or not slug[0].isalnum():
        slug = "c" + hashlib.sha256(name.encode("utf-8")).hexdigest()[:12]
    return f"local.{slug}"


def _write(archive: zipfile.ZipFile, name: str, data: bytes) -> None:
    info = zipfile.ZipInfo(name, date_time=FIXED_TIMESTAMP)
    info.compress_type = zipfile.ZIP_DEFLATED
    info.create_system = 3  # Unix, which is the host the installer validates
    info.external_attr = REGULAR_FILE_0644
    archive.writestr(info, data)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True, help="model directory, or a single .vrm file")
    parser.add_argument("--renderer", required=True, choices=["live2d", "vrm", "static"])
    parser.add_argument("--entry", help="entry file relative to input (default: the .vrm itself)")
    parser.add_argument("--name", required=True, help="display name")
    parser.add_argument("--author", required=True, help="who authored the model")
    parser.add_argument("--license", required=True, dest="licence", help="the licence you are relying on")
    parser.add_argument("--id", dest="character_id", help="character id (default derived from name)")
    parser.add_argument("--version", default="1.0.0")
    parser.add_argument("--out", required=True)
    args = parser.parse_args()

    source = Path(args.input).expanduser()
    output = Path(args.out).expanduser()

    if source.is_file():
        root, entries = source.parent, [(source.name, source)]
        entry_path = args.entry or source.name
    elif source.is_dir():
        root, entries = source, collect(source)
        if not args.entry:
            raise SystemExit("error: --entry is required when packaging a directory")
        entry_path = args.entry
    else:
        raise SystemExit(f"error: {source} not found")

    if not entries:
        raise SystemExit("error: no files to package")
    if len(entries) > MAXIMUM_FILES:
        raise SystemExit(f"error: {len(entries)} files exceeds the installer's {MAXIMUM_FILES} limit")
    if not any(name == entry_path for name, _ in entries):
        raise SystemExit(f"error: entry '{entry_path}' is not among the packaged files")

    total = sum(path.stat().st_size for _, path in entries)
    if total > MAXIMUM_EXPANDED_BYTES:
        raise SystemExit(f"error: {total} bytes exceeds the installer's expanded limit")

    character_id = args.character_id or _derive_id(args.name)
    if not _valid_identifier(character_id):
        raise SystemExit(
            f"error: character id '{character_id}' is not a valid identifier. "
            "The installer allows ASCII letters, digits, '.', '_' and '-' only, "
            "starting with a letter or digit. Pass --id explicitly."
        )

    assets = [
        {"path": name, "mediaType": media_type(path), "sha256": sha256(path)}
        for name, path in entries
    ]
    portrait = next((a["path"] for a in assets if a["path"].lower().endswith(".png")), None)

    manifest: dict[str, object] = {
        "schema": "joi.character.v1",
        "packageID": f"{character_id}.{args.version}",
        "characterID": character_id,
        "version": args.version,
        "displayName": args.name,
        "renderer": args.renderer,
        "entryPath": entry_path,
        "locales": ["zh-Hans"],
        "assets": assets,
        # No `source`: the installer accepts only remote HTTPS provenance, and a
        # local path is exactly what must not be recorded.
        "provenance": {"author": args.author, "license": args.licence},
    }
    if portrait:
        manifest["portraitPath"] = portrait

    output.parent.mkdir(parents=True, exist_ok=True)
    manifest_bytes = json.dumps(manifest, ensure_ascii=False, sort_keys=True).encode("utf-8")
    # allowZip64 off and a seekable file keep this inside the installer's
    # restricted profile: no ZIP64 records and no data descriptors.
    with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED, allowZip64=False) as archive:
        _write(archive, "manifest.json", manifest_bytes)
        for name, path in entries:
            _write(archive, name, path.read_bytes())

    print(f"wrote {output}")
    print(f"  renderer   {args.renderer}")
    print(f"  entry      {entry_path}")
    print(f"  files      {len(entries)} ({total / 1024 / 1024:.1f} MiB expanded)")
    print(f"  package    {output.stat().st_size / 1024 / 1024:.1f} MiB")
    print(f"  provenance {args.author} / {args.licence}")


if __name__ == "__main__":
    main()
