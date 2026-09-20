#!/usr/bin/env python3
"""Does this font actually have a glyph for this codepoint?

An icon that the font lacks renders as nothing, or as a tofu box, and the menu
looks broken in a way no exception reports. Reading the cmap answers it without
a dependency -- fontTools is not installed and a GUI launch could not rely on it
anyway. Handles cmap formats 4 and 12, which is what Nerd Fonts ship.
"""
import struct, sys


def supported(path):
    data = open(path, "rb").read()
    num_tables = struct.unpack(">H", data[4:6])[0]
    cmap_off = None
    for i in range(num_tables):
        rec = 12 + i * 16
        if data[rec:rec + 4] == b"cmap":
            cmap_off = struct.unpack(">I", data[rec + 8:rec + 12])[0]
            break
    if cmap_off is None:
        return set()

    n = struct.unpack(">H", data[cmap_off + 2:cmap_off + 4])[0]
    best = None
    for i in range(n):
        rec = cmap_off + 4 + i * 8
        pid, eid, off = struct.unpack(">HHI", data[rec:rec + 8])
        fmt = struct.unpack(">H", data[cmap_off + off:cmap_off + off + 2])[0]
        # Prefer a full-range format 12 table; fall back to format 4.
        if fmt == 12 or (fmt == 4 and best is None):
            best = (fmt, cmap_off + off)
            if fmt == 12:
                break
    if best is None:
        return set()

    fmt, off = best
    out = set()
    if fmt == 12:
        ngroups = struct.unpack(">I", data[off + 12:off + 16])[0]
        for g in range(ngroups):
            s, e, _ = struct.unpack(">III", data[off + 16 + g * 12:off + 28 + g * 12])
            if e - s < 0x10000:
                out.update(range(s, e + 1))
    else:
        seg2 = struct.unpack(">H", data[off + 6:off + 8])[0]
        segs = seg2 // 2
        ends = struct.unpack(">%dH" % segs, data[off + 14:off + 14 + seg2])
        starts_at = off + 16 + seg2
        starts = struct.unpack(">%dH" % segs, data[starts_at:starts_at + seg2])
        for s, e in zip(starts, ends):
            if s != 0xFFFF:
                out.update(range(s, e + 1))
    return out


if __name__ == "__main__":
    font = sys.argv[1]
    have = supported(font)
    missing = []
    for ch in sys.argv[2]:
        if ord(ch) not in have:
            missing.append("U+%04X" % ord(ch))
    print(" ".join(missing))
