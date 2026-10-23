#!/usr/bin/env python3
"""Guarded UI helper for testing InkControl over adb.

Taps only while org.neoport.inkcontrol owns the focused window, so a stray tap
can never land in another app.

  ui_tap.py find <text>                 print centre of first node whose text contains <text>
  ui_tap.py tap-text <text>             tap that node
  ui_tap.py tap-spinner-after <text>    tap the first Spinner after the node containing <text>
  ui_tap.py scroll-to <text>            swipe up until <text> is on screen (max 10 swipes)
  ui_tap.py scroll-back-to <text>       same, scrolling back towards the top
"""
import re
import subprocess
import sys
import time

PKG = "org.neoport.inkcontrol"


def adb(*a):
    return subprocess.run(["adb", *a], capture_output=True, text=True).stdout


def focused():
    for line in adb("shell", "dumpsys", "window").splitlines():
        if "mCurrentFocus" in line:
            return PKG in line
    return False


def nodes():
    adb("shell", "uiautomator", "dump", "/sdcard/Download/.ic.xml")
    x = adb("exec-out", "cat", "/sdcard/Download/.ic.xml")
    adb("shell", "rm", "-f", "/sdcard/Download/.ic.xml")
    return re.findall(r"<node [^>]*>", x)


def centre(n):
    b = list(map(int, re.search(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', n).groups()))
    return (b[0] + b[2]) // 2, (b[1] + b[3]) // 2


def text_of(n):
    m = re.search(r' text="([^"]*)"', n)
    return m.group(1) if m else ""


def find(t, spinner_after=False):
    ns = nodes()
    for i, n in enumerate(ns):
        if t in text_of(n):
            if not spinner_after:
                return centre(n)
            for m in ns[i + 1:i + 6]:
                if "android.widget.Spinner" in m:
                    return centre(m)
    return None


def tap(xy):
    if not focused():
        sys.exit("REFUSING to tap: InkControl is not the focused window")
    adb("shell", "input", "tap", str(xy[0]), str(xy[1]))


def main():
    cmd, t = sys.argv[1], " ".join(sys.argv[2:])
    if cmd in ("scroll-to", "scroll-back-to"):
        y0, y1 = ("1150", "450") if cmd == "scroll-to" else ("450", "1150")
        for _ in range(10):
            if find(t):
                print("visible"); return
            if not focused():
                sys.exit("REFUSING to swipe: InkControl is not the focused window")
            adb("shell", "input", "swipe", "360", y0, "360", y1, "400")
            time.sleep(1.5)
        sys.exit("not found: " + t)
    xy = find(t, spinner_after=(cmd == "tap-spinner-after"))
    if xy is None:
        sys.exit("not found: " + t)
    if cmd == "find":
        print(*xy)
    else:
        tap(xy); print("tapped", *xy)


if __name__ == "__main__":
    main()
