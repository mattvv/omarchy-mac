#!/usr/bin/env python3
"""Display scaling for the main screen, the macOS analogue of
omarchy-hyprland-monitor-scaling.

omarchy steps a Hyprland `scale` float (SCALES=(1 1.25 1.6 2 3 4)). macOS has
no scale float -- you pick a scaled resolution -- so this enumerates the modes
whose aspect matches the panel's native one (the real "Looks like" choices;
the 16:10 modes letterbox around the notch) and steps through those instead.
"""
from __future__ import annotations
import json, re, subprocess, sys

DP = "/opt/homebrew/bin/displayplacer"


def info():
    out = subprocess.run([DP, "list"], capture_output=True, text=True).stdout
    scr = {"id": "", "cur": "", "hz": "60", "depth": "8", "modes": []}
    m = re.search(r"Persistent screen id: (\S+)", out)
    if m: scr["id"] = m.group(1)
    m = re.search(r"^Resolution: (\d+x\d+)", out, re.M)
    if m: scr["cur"] = m.group(1)

    native_w = 0
    for line in out.splitlines():
        mm = re.match(r"\s*mode \d+: res:(\d+)x(\d+) hz:(\d+) color_depth:(\d+)(.*)", line)
        if not mm: continue
        w, h, hz, depth, rest = int(mm.group(1)), int(mm.group(2)), mm.group(3), mm.group(4), mm.group(5)
        if "scaling:on" not in rest:
            native_w = max(native_w, w)          # unscaled modes give the panel's native width
            continue
        scr["modes"].append({"w": w, "h": h, "hz": hz, "depth": depth,
                             "cur": "<-- current mode" in rest})
    # Keep the modes sharing the CURRENT mode's aspect -- those are the real
    # "Looks like" choices. Rounding to a fixed precision splits them
    # (1.544/1.545/1.546 are all the same 2880x1864 panel), so match on a
    # tolerance against the active mode instead.
    cur = next((md for md in scr["modes"] if md["cur"]), None)
    if cur:
        target = cur["w"] / cur["h"]
        scr["modes"] = [md for md in scr["modes"]
                        if abs(md["w"]/md["h"] - target) < 0.01]
    scr["modes"].sort(key=lambda md: md["w"])
    scr["native_w"] = native_w

    # omarchy's SCALE section shows a multiplier, not a resolution. macOS has
    # no scale float, but native/logical is the same quantity, and 2.0 is the
    # Retina default macOS calls "Default".
    if native_w:
        for md in scr["modes"]:
            md["scale"] = round(native_w / md["w"], 2)
    scaled = [md for md in scr["modes"] if md.get("scale")]
    if scaled:
        smallest = min(scaled, key=lambda m: m["scale"])
        largest  = max(scaled, key=lambda m: m["scale"])
        for md in scaled:
            sc = md["scale"]
            if abs(sc - 2.0) < 0.02:  md["name"] = "Default"
            elif md is largest:       md["name"] = "Largest Text"
            elif md is smallest:      md["name"] = "Most Space"
            elif sc > 2.0:            md["name"] = "Larger Text"
            else:                     md["name"] = "More Space"
    return scr


def apply(w, h, scr):
    cmd = (f'id:{scr["id"]} res:{w}x{h} hz:{scr["hz"]} '
           f'color_depth:{scr["depth"]} enabled:true scaling:on origin:(0,0) degree:0')
    subprocess.run([DP, cmd], capture_output=True, text=True)


def main():
    scr = info()
    if len(sys.argv) > 1 and sys.argv[1] in ("up", "down"):
        idx = next((i for i, md in enumerate(scr["modes"]) if md["cur"]), -1)
        if idx < 0: return
        # omarchy's "scaling up" means a BIGGER scale factor -> larger UI ->
        # fewer logical pixels, so "up" steps to the lower resolution.
        nxt = idx - 1 if sys.argv[1] == "up" else idx + 1
        if 0 <= nxt < len(scr["modes"]):
            apply(scr["modes"][nxt]["w"], scr["modes"][nxt]["h"], scr)
        return
    if len(sys.argv) > 2 and sys.argv[1] == "set":
        w, h = sys.argv[2].split("x")
        apply(int(w), int(h), scr)
        return
    print(json.dumps(scr))


main()
