#!/usr/bin/env python3
"""Build a custom `super` image for the InkPalm Plus from the stock super backup.

usage: build_super.py <stock_super.img> <new_system.img> <out_super.img>

Layout written (same geometry/block device as stock, metadata v10.0):
  group rockchip_dynamic_partitions_b, max = whole usable super
    system_b      <- new_system.img (the GSI, e.g. KompaktOS with our fixes)
    system_ext_b, vendor_b, product_b, odm_b <- copied byte-for-byte from stock slot B
  group rockchip_dynamic_partitions_a, max 0 bytes of extents: *_a partitions exist but empty
Stock slot-B's own system_b is dropped. The stock boot_b fstab first-stage-mounts all five
slot-B logical partitions (no avb flags), which is the combination proven by the DSU boots.
The same metadata is written to all 3 metadata slots, primary and backup copies.
"""
import hashlib
import os
import struct
import sys

SECTOR = 512
HDR_SIZE = 128  # v10.0
GEOM_OFF, META_OFF = 4096, 4096 * 3  # geometry (+ backup at 8192), then metadata slots


def read_meta(f, slot, max_size):
    f.seek(META_OFF + slot * max_size)
    h = f.read(HDR_SIZE)
    magic, maj, mino, hsz = struct.unpack("<IHHI", h[:12])
    assert magic == 0x414C5030 and (maj, mino, hsz) == (10, 0, HDR_SIZE), (hex(magic), maj, mino, hsz)
    tsz, = struct.unpack("<I", h[44:48])
    d = lambda o: struct.unpack("<III", h[o:o + 12])
    pt, et, gt, bt = d(80), d(92), d(104), d(116)
    t = f.read(tsz)
    groups = [(t[gt[0] + i * gt[2]:][:36], struct.unpack("<IQ", t[gt[0] + i * gt[2] + 36:][:12]))
              for i in range(gt[1])]
    exts = [struct.unpack("<QIQI", t[et[0] + i * et[2]:][:24]) for i in range(et[1])]
    parts = []
    for i in range(pt[1]):
        b = t[pt[0] + i * pt[2]:][:52]
        name = b[:36].split(b"\0")[0].decode()
        attr, fi, ne, gi = struct.unpack("<IIII", b[36:52])
        parts.append((name, attr, gi, [exts[j] for j in range(fi, fi + ne)]))
    bdev = t[bt[0]:bt[0] + bt[2]]
    return groups, parts, bdev


def name36(s):
    return s.encode().ljust(36, b"\0")


def main():
    stock, system_img, out = sys.argv[1:4]
    f = open(stock, "rb")
    f.seek(GEOM_OFF)
    geom = f.read(4096)
    assert struct.unpack("<I", geom[:4])[0] == 0x616C4467
    max_size, slots, _ = struct.unpack("<III", geom[40:52])
    groups, parts, bdev = read_meta(f, 1, max_size)  # metadata slot 1 = slot b view
    first_sector, align, align_off, dev_size = struct.unpack("<QIIQ", bdev[:24])
    assert dev_size == os.path.getsize(stock), "block device size != stock super image size"
    gnames = [g[0].split(b"\0")[0].decode() for g in groups]
    ga, gb = gnames.index("rockchip_dynamic_partitions_a"), gnames.index("rockchip_dynamic_partitions_b")
    stock_parts = {p[0]: p for p in parts}

    # Payload sources, in on-disk order.
    order = [("system_b", ("file", system_img))]
    for n in ("system_ext_b", "vendor_b", "product_b", "odm_b"):
        _, _, _, ex = stock_parts[n]
        assert len(ex) == 1 and ex[0][1] == 0, f"{n}: expected one linear extent"
        order.append((n, ("stock", ex[0][2] * SECTOR, ex[0][0] * SECTOR)))

    def size_of(src):
        return os.path.getsize(src[1]) if src[0] == "file" else src[2]

    # Allocate 1 MiB-aligned linear extents from the first logical sector.
    align_b = max(align, 1024 * 1024)
    pos = first_sector * SECTOR
    alloc = {}
    for n, src in order:
        sz = size_of(src)
        assert sz % SECTOR == 0
        alloc[n] = (pos, sz)
        pos = (pos + sz + align_b - 1) // align_b * align_b
    usable = dev_size - first_sector * SECTOR
    assert pos <= dev_size, f"does not fit: need {pos} of {dev_size}"
    print(f"layout uses {pos / 1e9:.3f} of {dev_size / 1e9:.3f} GB")

    # Tables: partitions (all stock names, *_a empty), extents, groups, block device.
    ptab, etab = b"", b""
    for name, attr, gi, _ in parts:
        if name in alloc:
            off, sz = alloc[name]
            fi, ne = len(etab) // 24, 1
            etab += struct.pack("<QIQI", sz // SECTOR, 0, off // SECTOR, 0)  # LINEAR, source 0
        else:
            fi, ne = 0, 0
        ptab += name36(name) + struct.pack("<IIII", attr, fi, ne, gi)
    gtab = b""
    for i, (gname, (flags, gmax)) in enumerate(groups):
        if i == gb:
            gmax = usable
        elif i == ga:
            gmax = 1024 * 1024  # nothing allocated in slot A
        gtab += gname + struct.pack("<IQ", flags, gmax)
    tables = ptab + etab + gtab + bdev
    n_parts, n_ext, n_grp = len(parts), len(etab) // 24, len(groups)
    descs = struct.pack("<III", 0, n_parts, 52) + struct.pack("<III", len(ptab), n_ext, 24) + \
        struct.pack("<III", len(ptab) + len(etab), n_grp, 48) + \
        struct.pack("<III", len(ptab) + len(etab) + len(gtab), 1, len(bdev))
    hdr = struct.pack("<IHHI", 0x414C5030, 10, 0, HDR_SIZE) + b"\0" * 32 + \
        struct.pack("<I", len(tables)) + hashlib.sha256(tables).digest() + descs
    assert len(hdr) == HDR_SIZE
    hdr = hdr[:12] + hashlib.sha256(hdr).digest() + hdr[44:]
    meta = hdr + tables
    assert len(meta) <= max_size

    with open(out, "wb") as o:
        o.truncate(dev_size)
        f.seek(0)
        o.write(f.read(GEOM_OFF))           # reserved area, as stock
        o.write(geom)                        # primary geometry
        o.write(geom)                        # backup geometry
        for copy in range(2):                # primary, then backup metadata region
            for s in range(slots):
                o.seek(META_OFF + (copy * slots + s) * max_size)
                o.write(meta.ljust(max_size, b"\0"))
        for n, src in order:
            off, sz = alloc[n]
            o.seek(off)
            if src[0] == "file":
                with open(src[1], "rb") as i:
                    while chunk := i.read(1 << 24):
                        o.write(chunk)
            else:
                f.seek(src[1])
                left = sz
                while left:
                    chunk = f.read(min(left, 1 << 24)); o.write(chunk); left -= len(chunk)
            print(f"  {n:14s} {sz / 1e9:.3f} GB @ {off}")
    print("wrote", out)


if __name__ == "__main__":
    main()
