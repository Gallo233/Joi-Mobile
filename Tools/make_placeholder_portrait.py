#!/usr/bin/env python3
"""Draw a self-authored placeholder portrait.

Character packages need a portrait, and every real model in this project is
rights-encumbered and off-repo. These are drawn from scratch so a demonstration
package can exist inside the repository without a rights question attached to it:
no third-party asset, nothing to clear, nothing to keep out of Git.

They are deliberately schematic. A placeholder that tried to look like a rendered
character would be making a claim the Android client cannot yet honour — there is
no renderer on that platform, and the static presentation is the honest one.

Usage:
    python3 Tools/make_placeholder_portrait.py --palette warm --out portrait.png
"""

from __future__ import annotations

import argparse
import struct
import zlib
from pathlib import Path

SIZE = 512

PALETTES = {
    # (background top, background bottom, figure, accent)
    "warm": ((0x2B, 0x1D, 0x1A), (0x5C, 0x33, 0x28), (0xF0, 0xDD, 0xCE), (0xC8, 0x7B, 0x53)),
    "cool": ((0x18, 0x1E, 0x2E), (0x2C, 0x3A, 0x5E), (0xDE, 0xE6, 0xF2), (0x6E, 0x8F, 0xC4)),
}


def lerp(a: int, b: int, t: float) -> int:
    return int(round(a + (b - a) * t))


def draw(palette: str) -> bytes:
    top, bottom, figure, accent = PALETTES[palette]
    rows = []
    cx, cy = SIZE / 2, SIZE * 0.42
    head_r = SIZE * 0.17
    # Shoulders are a wide circle whose top arc reads as a torso.
    sx, sy, sr = SIZE / 2, SIZE * 1.02, SIZE * 0.40

    for y in range(SIZE):
        row = bytearray()
        t = y / (SIZE - 1)
        bg = (lerp(top[0], bottom[0], t), lerp(top[1], bottom[1], t), lerp(top[2], bottom[2], t))
        for x in range(SIZE):
            head = ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5
            body = ((x - sx) ** 2 + (y - sy) ** 2) ** 0.5
            # A soft edge on both shapes; nothing here needs antialiasing beyond
            # one pixel of blend.
            if head <= head_r:
                colour = figure
            elif head <= head_r + 2:
                colour = tuple(lerp(figure[i], accent[i], (head - head_r) / 2) for i in range(3))
            elif body <= sr:
                colour = figure
            elif body <= sr + 2:
                colour = tuple(lerp(figure[i], accent[i], (body - sr) / 2) for i in range(3))
            else:
                # A ring of accent behind the head, so the two palettes read as
                # different characters at thumbnail size and not just as tints.
                halo = abs(head - head_r * 1.55)
                colour = tuple(lerp(bg[i], accent[i], max(0.0, 1 - halo / 14) * 0.55) for i in range(3))
            row += bytes(colour)
        rows.append(bytes(row))

    raw = b"".join(b"\x00" + row for row in rows)  # filter 0 on every scanline
    return png(raw)


def png(raw: bytes) -> bytes:
    def chunk(tag: bytes, body: bytes) -> bytes:
        return (
            struct.pack(">I", len(body))
            + tag
            + body
            + struct.pack(">I", zlib.crc32(tag + body) & 0xFFFFFFFF)
        )

    header = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0)  # 8-bit RGB
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", header)
        + chunk(b"IDAT", zlib.compress(raw, 9))
        + chunk(b"IEND", b"")
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--palette", choices=sorted(PALETTES), required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_bytes(draw(args.palette))
    print(f"wrote {args.out} ({args.out.stat().st_size} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
