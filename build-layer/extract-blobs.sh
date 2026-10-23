#!/usr/bin/env bash
# Collect the device-specific inputs the build needs, from YOUR OWN device backup, into a
# gitignored blobs dir. Nothing here is ever committed (proprietary Moaan/Rockchip/Google code).
# Runs on macOS (Homebrew e2fsprogs) or Linux. Copy the result to the build server afterwards.
#
#     build-layer/extract-blobs.sh [options]
#       --super IMG           stock super backup (default ~/InkPalm-Backup/partitions-full/super.img)
#       --slot a|b            stock slot whose system to read (default b, the stock active slot)
#       --from-dir DIR        take the six libs from DIR instead (e.g. ~/InkPalm-Images/stock-libs)
#       --kompakt-system IMG  take the boot animation from a KompaktOS system.img and rescale it
#       --bootanim ZIP        boot animation zip; rescaled to 720x1440 unless it already is
#       --out DIR             output dir (default build-layer/blobs)
#
# Output: libskia.so libdng_sdk.so libft2.so libandroidicu.so libicuuc.so libicui18n.so
#         [bootanimation.zip] SHA256SUMS SOURCES
# The stub libheif.so is NOT a blob: it is built from gsi/vendor-fix/heif_stub.c by the build.
set -euo pipefail
LOG_TAG=blobs
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO=$(cd "$HERE/.." && pwd)
# shellcheck source=lib/common.sh
. "$HERE/lib/common.sh"

SUPER=$HOME/InkPalm-Backup/partitions-full/super.img
SLOT=b
FROM_DIR=
KSYS=
BOOTANIM=
OUT=$HERE/blobs
while [ $# -gt 0 ]; do
    case "$1" in
        --super) SUPER=$2; shift 2 ;;
        --slot) SLOT=$2; shift 2 ;;
        --from-dir) FROM_DIR=$2; shift 2 ;;
        --kompakt-system) KSYS=$2; shift 2 ;;
        --bootanim) BOOTANIM=$2; shift 2 ;;
        --out) OUT=$2; shift 2 ;;
        -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
        *) die "unknown option $1 (see --help)" ;;
    esac
done
case "$SLOT" in a|b) ;; *) die "--slot must be a or b" ;; esac

need python3 od
mkdir -p "$OUT"
OUT=$(abs_dir "$OUT")
case "$OUT/" in
    "$REPO"/build-layer/blobs/*) ;;   # gitignored
    "$REPO"/*) die "$OUT is inside the repo but not build-layer/blobs/ (not gitignored)" ;;
esac
WORK=$(mktemp -d "${TMPDIR:-/tmp}/inkpalm-blobs.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
: > "$OUT/SOURCES"

# aarch64 ELF shared object? (magic, 64-bit class, e_machine 0xb7)
check_elf() {
    local h
    h=$(od -An -tx1 -N20 "$1" | tr -d ' \n')
    [ "${h:0:8}" = 7f454c46 ] && [ "${h:8:2}" = 02 ] && [ "${h:36:4}" = b700 ] ||
        die "$1 is not an aarch64 ELF (header $h)"
}

if [ -n "$FROM_DIR" ]; then
    stage "libraries from $FROM_DIR"
    for e in $STOCK_LIBS; do
        n=${e%%:*}
        [ -f "$FROM_DIR/$n" ] || die "missing $FROM_DIR/$n"
        cp "$FROM_DIR/$n" "$OUT/$n"
        echo "$n <- $FROM_DIR/$n" >> "$OUT/SOURCES"
    done
else
    stage "libraries from stock super ($SUPER, system_$SLOT)"
    [ -f "$SUPER" ] || die "no super image at $SUPER (use --super or --from-dir)"
    DEBUGFS=$(find_debugfs) || die "debugfs not found (macOS: brew install e2fsprogs; Linux: apt install e2fsprogs)"
    SYS=$WORK/system.img
    if command -v lpunpack >/dev/null 2>&1; then
        lpunpack -p "system_$SLOT" "$SUPER" "$WORK" >/dev/null
        mv "$WORK/system_$SLOT.img" "$SYS"
    else
        # No lpunpack on macOS: read the LP metadata with tools/build_super.py's parser
        # (metadata v10.0, which is what this device's super uses) and copy the linear extents.
        python3 -I - "$REPO/tools" "$SUPER" "$SLOT" "$SYS" <<'PY'
import struct, sys
sys.path.insert(0, sys.argv[1])
import build_super as bs
sup, slot, out = sys.argv[2], sys.argv[3], sys.argv[4]
with open(sup, "rb") as f:
    f.seek(bs.GEOM_OFF)
    geom = f.read(4096)
    assert struct.unpack("<I", geom[:4])[0] == 0x616C4467, "not an LP super image"
    max_size, = struct.unpack("<I", geom[40:44])
    _, parts, _ = bs.read_meta(f, 0 if slot == "a" else 1, max_size)
    want = "system_" + slot
    ext = next((p[3] for p in parts if p[0] == want), None)
    assert ext, "no %s in the super metadata" % want
    with open(out, "wb") as o:
        for nsec, ttype, data, _src in ext:
            assert ttype == 0, "non-linear extent in %s" % want
            f.seek(data * bs.SECTOR)
            left = nsec * bs.SECTOR
            while left:
                b = f.read(min(left, 1 << 24)); o.write(b); left -= len(b)
print("extracted", want)
PY
    fi
    # Stock Android 11 is system-as-root: the image's /system/lib64 is /system/lib64 on device.
    take() {  # take <path in image> <dest>
        "$DEBUGFS" -R "dump -p $1 $2" "$3" >/dev/null 2>&1 && [ -s "$2" ]
    }
    ART_APEX=
    for e in $STOCK_LIBS; do
        n=${e%%:*}; where=${e#*:}
        if [ "$where" = system ]; then
            take "/system/lib64/$n" "$OUT/$n" "$SYS" || take "/lib64/$n" "$OUT/$n" "$SYS" ||
                die "$n not found in stock system_$SLOT"
            echo "$n <- $SUPER system_$SLOT:/system/lib64/$n" >> "$OUT/SOURCES"
            continue
        fi
        # ART APEX: flattened dir on this device (per gsi/vendor-fix/README.md); a packed
        # .apex is handled too. UNVERIFIED: the packed-APEX path was never needed here.
        if take "/system/apex/com.android.art.release/lib64/$n" "$OUT/$n" "$SYS"; then
            echo "$n <- $SUPER system_$SLOT:/system/apex/com.android.art.release/lib64/$n" >> "$OUT/SOURCES"
            continue
        fi
        if [ -z "$ART_APEX" ]; then
            for a in com.android.art.release.apex com.android.art.apex; do
                if take "/system/apex/$a" "$WORK/art.apex" "$SYS"; then
                    need unzip
                    unzip -p "$WORK/art.apex" apex_payload.img > "$WORK/art_payload.img"
                    ART_APEX=$a; break
                fi
            done
            [ -n "$ART_APEX" ] || die "ART APEX not found in stock system_$SLOT"
        fi
        take "/lib64/$n" "$OUT/$n" "$WORK/art_payload.img" || die "$n not in $ART_APEX"
        echo "$n <- $SUPER system_$SLOT:/system/apex/$ART_APEX!/lib64/$n" >> "$OUT/SOURCES"
    done
fi
for e in $STOCK_LIBS; do check_elf "$OUT/${e%%:*}"; done

if [ -n "$KSYS" ] || [ -n "$BOOTANIM" ]; then
    stage "boot animation"
    if [ -n "$KSYS" ]; then
        DEBUGFS=${DEBUGFS:-$(find_debugfs)} || die "debugfs not found"
        BOOTANIM=$WORK/bootanimation-src.zip
        "$DEBUGFS" -R "dump -p /system/product/media/bootanimation.zip $BOOTANIM" "$KSYS" >/dev/null 2>&1
        [ -s "$BOOTANIM" ] || die "no /system/product/media/bootanimation.zip in $KSYS"
        echo "bootanimation.zip <- $KSYS:/system/product/media/bootanimation.zip (rescaled)" >> "$OUT/SOURCES"
    else
        echo "bootanimation.zip <- $BOOTANIM" >> "$OUT/SOURCES"
    fi
    need unzip
    size=$(unzip -p "$BOOTANIM" desc.txt | head -1 | awk '{print $1 "x" $2}')
    if [ "$size" = 720x1440 ]; then
        cp "$BOOTANIM" "$OUT/bootanimation.zip"
    else
        log "rescaling $size -> 720x1440 with tools/bootanim/rescale_bootanim.py (needs Pillow)"
        python3 "$REPO/tools/bootanim/rescale_bootanim.py" "$BOOTANIM" "$OUT/bootanimation.zip"
    fi
elif [ ! -f "$OUT/bootanimation.zip" ]; then
    warn "no boot animation given (--kompakt-system or --bootanim); build.sh needs bootanimation.zip"
fi

stage "checksums"
( cd "$OUT" && for f in *.so bootanimation.zip; do
      if [ -f "$f" ]; then printf '%s  %s\n' "$(sha256_of "$f")" "$f"; fi
  done ) > "$OUT/SHA256SUMS"
cat "$OUT/SHA256SUMS" >&2
log "done: $OUT"
log "copy to the server, e.g.: rsync -av $OUT/ <server>:InkPalm-KompaktOS/build-layer/blobs/"
