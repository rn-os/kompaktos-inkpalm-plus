#!/usr/bin/env python3
"""Print 'ok W H distinct_colors nonuniform_fraction' for an 8-bit PNG (pure stdlib), or 'err ...'."""
import struct, sys, zlib

def main(p):
    try:
        d = open(p, 'rb').read()
    except OSError as e:
        return 'err cannot read ' + str(e)
    if d[:8] != b'\x89PNG\r\n\x1a\n':
        return 'err not a png (%d bytes)' % len(d)
    pos, idat, w = 8, b'', None
    while pos < len(d):
        n, t = struct.unpack('>I4s', d[pos:pos + 8])
        c = d[pos + 8:pos + 8 + n]
        if t == b'IHDR':
            w, h, bd, ct = struct.unpack('>IIBB', c[:10])
        elif t == b'IDAT':
            idat += c
        pos += 12 + n
    if w is None or bd != 8 or ct not in (0, 2, 4, 6):
        return 'err unsupported png'
    bpp = {0: 1, 2: 3, 4: 2, 6: 4}[ct]
    raw = zlib.decompress(idat)
    stride = w * bpp
    prev = bytearray(stride)
    seen, first, diff = set(), None, 0
    i = 0
    for _ in range(h):
        f = raw[i]; line = bytearray(raw[i + 1:i + 1 + stride]); i += 1 + stride
        for x in range(stride):
            a = line[x - bpp] if x >= bpp else 0
            b = prev[x]; c = prev[x - bpp] if x >= bpp else 0
            if f == 1: line[x] = (line[x] + a) & 255
            elif f == 2: line[x] = (line[x] + b) & 255
            elif f == 3: line[x] = (line[x] + ((a + b) >> 1)) & 255
            elif f == 4:
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                pr = a if pa <= pb and pa <= pc else (b if pb <= pc else c)
                line[x] = (line[x] + pr) & 255
        prev = line
        for x in range(0, stride, bpp * 4):          # sample every 4th pixel
            px = bytes(line[x:x + bpp])
            if first is None: first = px
            elif px != first: diff += 1
            if len(seen) < 4096: seen.add(px)
    total = max(1, h * (w // 4 + 1))
    return 'ok %d %d %d %.4f' % (w, h, len(seen), diff / total)

print(main(sys.argv[1]))
