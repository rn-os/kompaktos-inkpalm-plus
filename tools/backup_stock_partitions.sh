#!/bin/zsh
# Full stock partition backup, read-only, taken while booted into a userdebug GSI test image
# (adb root). Moaan's loader blocks reads past 32 MiB and Maskrom failed on the Mac, so this
# is how we image super (stock system/vendor/odm/product/system_ext, both slots), boot, vbmeta,
# dtbo, etc. Nothing on the device is written.  Restore notes: docs/REVERT.md
#   usage: tools/backup_stock_partitions.sh [out_dir]
set -u
OUT=${1:-$HOME/InkPalm-Backup/partitions-full}
. "${0:A:h}/lib/inkpalm_os.sh"
ip_require_gsi     # refuses on stock (system fingerprint contains rockchip/Moaan) or non-GSI
ip_root_or_die     # reads raw block devices: needs adb root
mkdir -p "$OUT"
# Small partitions first, super last (5 GiB). userdata is not imaged (live, encrypted, backed up as files).
for p in security uboot_a uboot_b waveform trust_a trust_b misc dtbo_a dtbo_b vbmeta_a vbmeta_b \
         boot_a boot_b backup cache metadata baseparameter logo_a logo_b super; do
  sz=$(adb shell blockdev --getsize64 /dev/block/by-name/$p | tr -d '\r')
  adb exec-out "dd if=/dev/block/by-name/$p bs=4M 2>/dev/null" > "$OUT/$p.img"
  got=$(stat -f %z "$OUT/$p.img")
  dev=$(adb shell "sha256sum /dev/block/by-name/$p" | cut -d' ' -f1)
  loc=$(shasum -a 256 "$OUT/$p.img" | cut -d' ' -f1)
  [ "$got" = "$sz" ] && [ "$dev" = "$loc" ] && s=OK || s=MISMATCH
  printf '%-14s %12s bytes  %s  %s\n' $p $got $loc $s | tee -a "$OUT/SHA256SUMS.txt"
done
# Cross-check with the loader-mode dump of the first 32 MiB (security/uboot/waveform/trust/misc).
echo "compare with ~/InkPalm-Backup/partitions/SHA256SUMS for the 32 MiB loader-mode copies"
