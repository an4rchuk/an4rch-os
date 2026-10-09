#!/usr/bin/env python3
"""Pick a comfortable scale for each display (used by `anarch-display autoscale`).

    autoscale.py < hyprctl-monitors.json      prints "NAME SCALE MODE" per display

The screen's physical size comes from its EDID (in /sys/class/drm). Without
one (virtual machines, some TVs and adapters) the resolution decides. Only
scales that divide the resolution exactly are used, so text stays sharp.
"""
import glob
import json
import math
import os
import sys
from fractions import Fraction

CANDIDATES = [Fraction(1), Fraction(5, 4), Fraction(3, 2), Fraction(8, 5), Fraction(5, 3),
              Fraction(7, 4), Fraction(2), Fraction(5, 2), Fraction(3)]
LAPTOP = ("eDP", "LVDS", "DSI")


def edid_size_cm(name):
    """(width, height) in cm from the connector's EDID, or None."""
    for path in glob.glob(f"/sys/class/drm/card*-{name}/edid"):
        try:
            data = open(path, "rb").read()
        except OSError:
            continue
        if len(data) >= 23 and data[:8] == b"\x00\xff\xff\xff\xff\xff\xff\x00":
            w, h = data[21], data[22]
            if w >= 10 and h >= 6:      # 0 means unknown; tiny values are bogus
                return w, h
    return None


def ideal(mon):
    """The scale this display would ideally have (not yet snapped)."""
    name, w, h = mon["name"], mon["width"], mon["height"]
    laptop = name.startswith(LAPTOP)
    size = edid_size_cm(name)
    if size:
        diag_in = math.hypot(*size) / 2.54
        ppi = math.hypot(w, h) / diag_in
        # A laptop is closer to the eyes than a desktop monitor.
        return ppi / (125 if laptop else 110)
    # No physical size: go by resolution.
    if laptop:
        return 2 if w >= 3000 else 1.6 if w >= 2560 else 1.25 if w >= 2160 else 1
    return 2 if w >= 5120 else 1.5 if w >= 3840 else 1


def snap(w, h, want):
    """The candidate nearest `want` that divides the resolution exactly."""
    if want < 1.12:
        return Fraction(1)
    best = Fraction(1)
    for s in CANDIDATES:
        if (Fraction(w) / s).denominator != 1 or (Fraction(h) / s).denominator != 1:
            continue
        if abs(float(s) - want) < abs(float(best) - want):
            best = s
    return best


def main():
    try:
        monitors = json.load(sys.stdin)
    except ValueError:
        return
    for mon in monitors:
        if mon.get("disabled") or not mon.get("width"):
            continue
        s = snap(mon["width"], mon["height"], ideal(mon))
        txt = str(int(s)) if s.denominator == 1 else f"{float(s):.6g}"
        mode = f'{mon["width"]}x{mon["height"]}@{round(mon.get("refreshRate", 60), 2):g}'
        print(mon["name"], txt, mode)


if __name__ == "__main__":
    main()
