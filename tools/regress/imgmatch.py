#!/usr/bin/env python3
"""imgmatch.py <screenshot.png> <standby.png> -> prints "<best_mean_abs_diff> <rotation>".
The standby image is the panel's 720x1440 portrait buffer (landscape faces are pre-rotated into
it); a screenshot is in display orientation. Compare grayscale at 1/4 size under 0/90/180/270."""
import sys
from PIL import Image, ImageChops, ImageStat

shot = Image.open(sys.argv[1]).convert("L")
ref = Image.open(sys.argv[2]).convert("L")
best = None
for rot in (0, 90, 180, 270):
    r = ref.rotate(rot, expand=True)
    if r.size != shot.size:
        continue
    a = shot.resize((r.width // 4, r.height // 4))
    b = r.resize((r.width // 4, r.height // 4))
    d = ImageStat.Stat(ImageChops.difference(a, b)).mean[0]
    if best is None or d < best[0]:
        best = (d, rot)
print("%.2f %d" % best if best else "999 -1")
