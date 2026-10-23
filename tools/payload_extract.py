#!/usr/bin/env python3
"""Extract partitions from an Android A/B OTA payload.bin (full OTAs only).

usage: payload_extract.py <payload.bin | ota.zip> <out_dir> [partition ...]
       payload_extract.py <payload.bin | ota.zip> --list

Supports the operations full OTAs use: REPLACE, REPLACE_BZ, REPLACE_XZ, ZERO, DISCARD.
The DeltaArchiveManifest protobuf is decoded by hand (no protobuf dependency).
"""
import bz2
import lzma
import os
import struct
import sys
import zipfile

REPLACE, REPLACE_BZ, ZERO, DISCARD, REPLACE_XZ = 0, 1, 6, 7, 8


def varint(b, i):
    v = s = 0
    while True:
        c = b[i]; i += 1
        v |= (c & 0x7F) << s
        if c < 0x80:
            return v, i
        s += 7


def fields(b):
    """Yield (field_number, wire_type, value) for a protobuf message."""
    i = 0
    while i < len(b):
        key, i = varint(b, i)
        f, wt = key >> 3, key & 7
        if wt == 0:
            v, i = varint(b, i)
        elif wt == 1:
            v = b[i:i + 8]; i += 8
        elif wt == 2:
            n, i = varint(b, i); v = b[i:i + n]; i += n
        elif wt == 5:
            v = b[i:i + 4]; i += 4
        else:
            raise ValueError("unsupported wire type %d" % wt)
        yield f, wt, v


def parse_manifest(m):
    block_size, parts = 4096, []
    for f, _, v in fields(m):
        if f == 3:
            block_size = v
        elif f == 13:  # PartitionUpdate
            name, ops, size = None, [], None
            for pf, _, pv in fields(v):
                if pf == 1:
                    name = pv.decode()
                elif pf == 8:  # InstallOperation
                    op = {"type": 0, "off": 0, "len": 0, "dst": []}
                    for of, _, ov in fields(pv):
                        if of == 1: op["type"] = ov
                        elif of == 2: op["off"] = ov
                        elif of == 3: op["len"] = ov
                        elif of == 6:  # Extent
                            e = dict(fields_to_dict(ov))
                            op["dst"].append((e.get(1, 0), e.get(2, 0)))
                    ops.append(op)
                elif pf == 7:  # new_partition_info
                    size = dict(fields_to_dict(pv)).get(1)
            parts.append((name, size, ops))
    return block_size, parts


def fields_to_dict(b):
    return [(f, v) for f, _, v in fields(b)]


def open_payload(path):
    if zipfile.is_zipfile(path):
        z = zipfile.ZipFile(path)
        info = z.getinfo("payload.bin")
        assert info.compress_type == zipfile.ZIP_STORED, "payload.bin must be stored"
        f = open(path, "rb")
        f.seek(info.header_offset)
        hdr = f.read(30)
        n, m = struct.unpack("<HH", hdr[26:30])
        return f, info.header_offset + 30 + n + m
    return open(path, "rb"), 0


def main():
    src, out = sys.argv[1], sys.argv[2]
    f, base = open_payload(src)
    f.seek(base)
    magic, ver, msize = struct.unpack(">4sQQ", f.read(20))
    assert magic == b"CrAU", "not a payload"
    sig = struct.unpack(">I", f.read(4))[0] if ver >= 2 else 0
    block_size, parts = parse_manifest(f.read(msize))
    data = base + 20 + (4 if ver >= 2 else 0) + msize + sig
    if out == "--list":
        for name, size, ops in parts:
            types = sorted({o["type"] for o in ops})
            print(f"{name:20s} {size or 0:>12} bytes  ops={len(ops)} types={types}")
        return
    want = set(sys.argv[3:])
    os.makedirs(out, exist_ok=True)
    for name, size, ops in parts:
        if want and name not in want:
            continue
        dst = os.path.join(out, name + ".img")
        with open(dst, "wb") as o:
            if size:
                o.truncate(size)
            for op in ops:
                f.seek(data + op["off"])
                blob = f.read(op["len"])
                t = op["type"]
                if t == REPLACE_BZ:
                    blob = bz2.decompress(blob)
                elif t == REPLACE_XZ:
                    blob = lzma.decompress(blob)
                elif t in (ZERO, DISCARD):
                    blob = None
                elif t != REPLACE:
                    sys.exit(f"{name}: unsupported op type {t} (incremental OTA?)")
                pos = 0
                for start, n in op["dst"]:
                    o.seek(start * block_size)
                    ln = n * block_size
                    o.write(b"\0" * ln if blob is None else blob[pos:pos + ln])
                    pos += ln
        print(f"{name}: {os.path.getsize(dst)} bytes -> {dst}")


if __name__ == "__main__":
    main()
