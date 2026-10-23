#!/usr/bin/env python3
"""Rescale an Android bootanimation.zip to a new screen size (default 720x1440).

usage: rescale_bootanim.py IN.zip OUT.zip [--width 720 --height 1440] [--preview PREVIEW.png]
Frames are scaled by the width ratio (LANCZOS, or NEAREST for <=2 colours), then padded
vertically/centred with the artwork's own edge colour. desc.txt gets the new size; all other
lines, member order, and non-PNG members are preserved. Output is ZIP_STORED (required by Android).
"""
import argparse, io, sys, zipfile
from collections import Counter
from PIL import Image

ap = argparse.ArgumentParser()
ap.add_argument("src"); ap.add_argument("dst")
ap.add_argument("--width", type=int, default=720)
ap.add_argument("--height", type=int, default=1440)
ap.add_argument("--preview")
a = ap.parse_args()

zin = zipfile.ZipFile(a.src)
desc = zin.read("desc.txt").decode().splitlines()
ow, oh, fps = desc[0].split()[:3]
ow, oh = int(ow), int(oh)
scale = a.width / ow
nh = round(oh * scale)
if nh > a.height:
    sys.exit(f"scaled height {nh} exceeds target {a.height}")

def bg_of(im):
    px = im.convert("RGB"); w, h = px.size
    edge = [px.getpixel((x, y)) for x in range(w) for y in (0, h - 1)] + \
           [px.getpixel((x, y)) for y in range(h) for x in (0, w - 1)]
    return Counter(edge).most_common(1)[0][0]

def conv(im):
    bg = bg_of(im)
    ncol = len(im.convert("RGB").getcolors(1 << 24) or range(99))
    rs = Image.NEAREST if ncol <= 2 else Image.LANCZOS
    sc = im.convert("RGB").resize((a.width, nh), rs)
    out = Image.new("RGB", (a.width, a.height), bg)
    out.paste(sc, (0, (a.height - nh) // 2))
    return out

frames = []
with zipfile.ZipFile(a.dst, "w", zipfile.ZIP_STORED) as zout:
    for zi in zin.infolist():
        data = zin.read(zi.filename)
        if zi.filename == "desc.txt":
            desc[0] = f"{a.width} {a.height} {fps}"
            data = ("\n".join(desc) + "\n").encode()
        elif zi.filename.lower().endswith(".png"):
            im = Image.open(io.BytesIO(data))
            if im.size != (ow, oh):
                print("warn: unexpected size", zi.filename, im.size)
            out = conv(im)
            frames.append(out)
            b = io.BytesIO(); out.save(b, "PNG", optimize=True); data = b.getvalue()
        n = zipfile.ZipInfo(zi.filename, zi.date_time)
        n.compress_type = zipfile.ZIP_STORED
        n.external_attr = zi.external_attr
        n.create_system = zi.create_system
        zout.writestr(n, data)
print(f"{len(frames)} frames -> {a.dst} ({a.width}x{a.height}, bg from edges)")
if a.preview and frames:
    pick = [frames[0], frames[len(frames) // 2], frames[-1]]
    sheet = Image.new("RGB", (a.width * 3 + 40, a.height), (128, 128, 128))
    for i, f in enumerate(pick):
        sheet.paste(f, (i * (a.width + 20), 0))
    sheet.save(a.preview)
