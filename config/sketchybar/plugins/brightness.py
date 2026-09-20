#!/usr/bin/env python3
"""Brightness via the private DisplayServices framework.

The public routes are dead ends on Apple Silicon built-in panels: the
`brightness` CLI fails with -536870201, ioreg's IODisplayParameters
"brightness" is pinned at 32768/65536, and "rawBrightness" never moves.
DisplayServicesGetBrightness/SetBrightness work, and are what Mac brightness
tools actually use.
"""
import ctypes, sys

_cg = ctypes.CDLL('/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics')
_cg.CGMainDisplayID.restype = ctypes.c_uint32
_ds = ctypes.CDLL('/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices')
_ds.DisplayServicesGetBrightness.argtypes = [ctypes.c_uint32, ctypes.POINTER(ctypes.c_float)]
_ds.DisplayServicesGetBrightness.restype = ctypes.c_int
_ds.DisplayServicesSetBrightness.argtypes = [ctypes.c_uint32, ctypes.c_float]
_ds.DisplayServicesSetBrightness.restype = ctypes.c_int


def get():
    b = ctypes.c_float(-1)
    did = _cg.CGMainDisplayID()
    if _ds.DisplayServicesGetBrightness(did, ctypes.byref(b)) != 0 or b.value < 0:
        return None
    return b.value


def put(pct):
    pct = max(0.0, min(1.0, pct))
    _ds.DisplayServicesSetBrightness(_cg.CGMainDisplayID(), ctypes.c_float(pct))
    return pct


if __name__ == "__main__":
    if len(sys.argv) > 2 and sys.argv[1] == "set":
        print(int(round(put(float(sys.argv[2]) / 100.0) * 100)))
    elif len(sys.argv) > 1 and sys.argv[1] in ("up", "down"):
        cur = get() or 0.5
        step = 0.0625 if sys.argv[1] == "up" else -0.0625
        print(int(round(put(cur + step) * 100)))
    else:
        v = get()
        print("" if v is None else int(round(v * 100)))
