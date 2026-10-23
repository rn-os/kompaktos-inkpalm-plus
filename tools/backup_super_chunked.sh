#!/bin/zsh
# Image /dev/block/by-name/super in 512 MiB chunks (one adb stream per chunk, each sha256-checked
# against the device), then join. A single 5 GiB adb stream stalled. Read-only; needs GSI root.
set -u
OUT=${1:-$HOME/InkPalm-Backup/partitions-full}
. "${0:A:h}/lib/inkpalm_os.sh"
ip_require_gsi     # refuses on stock (system fingerprint contains rockchip/Moaan) or non-GSI
ip_root_or_die
mkdir -p "$OUT/super.chunks"
SZ=$(adb shell blockdev --getsize64 /dev/block/by-name/super | tr -d '\r')
CH=$((512*1024*1024)); N=$(( (SZ + CH - 1) / CH ))
for i in $(seq 0 $((N-1))); do
  f=$(printf '%s/super.chunks/%02d' "$OUT" $i)
  for try in 1 2 3; do
    perl -e 'alarm 300; exec @ARGV' adb exec-out "dd if=/dev/block/by-name/super bs=4M skip=$((i*128)) count=128 2>/dev/null" > $f
    dev=$(adb shell "dd if=/dev/block/by-name/super bs=4M skip=$((i*128)) count=128 2>/dev/null | sha256sum" | cut -d' ' -f1)
    [ "$(shasum -a 256 $f | cut -d' ' -f1)" = "$dev" ] && break
    echo "chunk $i try $try mismatch, retrying"
  done
  echo "chunk $i/$((N-1)): $(stat -f %z $f) bytes ok"
done
cat "$OUT"/super.chunks/* > "$OUT/super.img"
[ "$(stat -f %z "$OUT/super.img")" = "$SZ" ] && echo "super.img complete: $SZ bytes" || echo "SIZE MISMATCH"
printf '%-14s %12s bytes  %s  %s\n' super $SZ $(shasum -a 256 "$OUT/super.img" | cut -d' ' -f1) OK >> "$OUT/SHA256SUMS.txt"
rm -rf "$OUT/super.chunks"
