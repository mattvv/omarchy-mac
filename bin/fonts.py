#!/usr/bin/env python3
"""Which monospace fonts are actually installed.

The menu cannot hardcode a font list: it differs per machine, and offering a
font that is not there is the same failure as a row that does nothing. So the
font files are read directly -- family name from the `name` table, fixed-pitch
flag from `post` -- with no dependency, because fontTools is not installed and a
GUI launch could not rely on it anyway.
"""
from __future__ import annotations
import os, struct, sys
from pathlib import Path

FONT_DIRS = [Path.home() / "Library/Fonts", Path("/Library/Fonts"),
             Path("/System/Library/Fonts")]


def tables(data: bytes) -> dict:
    if data[:4] not in (b"\x00\x01\x00\x00", b"OTTO", b"true"):
        return {}
    count = struct.unpack(">H", data[4:6])[0]
    out = {}
    for i in range(count):
        rec = 12 + i * 16
        if rec + 16 > len(data):
            break
        tag = data[rec:rec + 4]
        offset, length = struct.unpack(">II", data[rec + 8:rec + 16])
        out[tag] = (offset, length)
    return out


def family_name(data: bytes, name_table) -> str:
    offset, _ = name_table
    count, strings = struct.unpack(">H", data[offset + 2:offset + 4])[0], \
        struct.unpack(">H", data[offset + 4:offset + 6])[0]
    best = ""
    for i in range(count):
        rec = offset + 6 + i * 12
        platform, encoding, lang, name_id, length, str_off = \
            struct.unpack(">HHHHHH", data[rec:rec + 12])
        if name_id != 1:
            continue
        raw = data[offset + strings + str_off: offset + strings + str_off + length]
        try:
            text = raw.decode("utf-16-be") if platform == 3 else raw.decode("mac-roman")
        except Exception:
            continue
        # Prefer the Windows/Unicode record; fall back to whatever decoded.
        if platform == 3:
            return text.strip()
        best = best or text.strip()
    return best


def is_monospace(data: bytes, post_table) -> bool:
    offset, _ = post_table
    # isFixedPitch is a 32-bit field at offset 12 of the post table.
    if offset + 16 > len(data):
        return False
    return struct.unpack(">I", data[offset + 12:offset + 16])[0] != 0


# A font file per weight means a "family" per weight -- JetBrainsMono NFM Light,
# Medium, Thin and so on are one choice, not seven.
WEIGHTS = ("Thin", "ExtraLight", "Light", "Regular", "Medium", "SemiBold",
           "Bold", "ExtraBold", "Black", "Italic", "Oblique")


def base_family(name: str) -> str:
    changed = True
    while changed:
        changed = False
        for weight in WEIGHTS:
            if name.endswith(" " + weight):
                name = name[: -(len(weight) + 1)]
                changed = True
    return name.strip()


def families() -> list:
    found = {}
    for directory in FONT_DIRS:
        try:
            entries = sorted(os.scandir(directory), key=lambda e: e.name)
        except OSError:
            continue
        for entry in entries:
            if not entry.name.lower().endswith((".ttf", ".otf")):
                continue
            try:
                with open(entry.path, "rb") as handle:
                    data = handle.read()
            except OSError:
                continue
            t = tables(data)
            if b"name" not in t or b"post" not in t:
                continue
            try:
                if not is_monospace(data, t[b"post"]):
                    continue
                name = family_name(data, t[b"name"])
            except Exception:
                continue
            name = base_family(name)
            # Names beginning with a dot are Apple's hidden system faces; they
            # are installed but are not fonts anyone chooses.
            if name and not name.startswith(".") and name not in found:
                found[name] = entry.path
    return sorted(found.items())


def installed(needle: str) -> bool:
    """Is a family whose name contains this present?

    Used for the install rows' ticks. `brew list --cask` would answer it too,
    but six of those on every menu open is six subprocesses and a second of
    waiting; the font files are already being read."""
    needle = needle.lower()
    return any(needle in name.lower() for name, _ in families())


if __name__ == "__main__":
    import sys
    if len(sys.argv) > 2 and sys.argv[1] == "has":
        sys.exit(0 if installed(sys.argv[2]) else 1)
    for name, path in families():
        print(f"{name}\t{path}")
