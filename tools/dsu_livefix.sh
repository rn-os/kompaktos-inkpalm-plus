#!/bin/zsh
# Run while the InkPalm is booted into the DSU (LineageOS GSI, userdebug).
# 1. adb root, pull /vendor and /odm (for offline dependency analysis)
# 2. layer stock system libs (vlib64 bundle) over /vendor/lib64 for THIS BOOT ONLY
#    (tmp overlay mount; nothing on vendor/odm/stock partitions is written)
# 3. restart the vendor composer + SurfaceFlinger, report every missing-library error
#   usage: tools/dsu_livefix.sh [bundle_dir]
set -u
B=${1:-$HOME/InkPalm-Images/stock-libs/vlib64}
OUT=$HOME/InkPalm-Images/dsu-boot-$(date +%Y%m%d-%H%M%S)
mkdir -p "$OUT"

[ "$(adb shell getprop ro.product.name | tr -d '\r')" = lineage_arm64_bvN ] || { echo "not in the DSU image"; exit 1; }
adb root >/dev/null; sleep 3; adb wait-for-device
[ "$(adb shell id -u | tr -d '\r')" = 0 ] || { echo "adb root failed"; exit 1; }

echo "== saving logs and vendor/odm to $OUT"
adb logcat -d -b all > "$OUT/logcat-before.txt"
adb shell getprop > "$OUT/getprop.txt"
for p in vendor odm; do adb pull /$p "$OUT/$p" >/dev/null 2>&1; echo "$p: $(find "$OUT/$p" -type f | wc -l | tr -d ' ') files"; done
grep -h -o -E 'library "[^"]+" not found: needed by [^ ]+' "$OUT/logcat-before.txt" | sort | uniq -c | sort -rn > "$OUT/missing-before.txt"
echo "== missing libraries before the fix:"; cat "$OUT/missing-before.txt"

echo "== layering $(ls "$B" | wc -l | tr -d ' ') libs over /vendor/lib64 (tmp, this boot only)"
adb shell rm -rf /data/local/tmp/vlib64
adb push "$B" /data/local/tmp/vlib64 >/dev/null
adb shell 'chcon -R u:object_r:vendor_file:s0 /data/local/tmp/vlib64 &&
  chmod 644 /data/local/tmp/vlib64/* &&
  mount -t overlay overlay -o lowerdir=/data/local/tmp/vlib64:/vendor/lib64 /vendor/lib64 &&
  echo mounted && ls /vendor/lib64/libskia.so'
adb logcat -c
adb shell 'setprop ctl.restart vendor.hwcomposer-2-1; sleep 2; setprop ctl.restart surfaceflinger'
sleep 25
adb logcat -d -b all > "$OUT/logcat-after.txt"
echo "== after: composer=$(adb shell getprop init.svc.vendor.hwcomposer-2-1) surfaceflinger=$(adb shell getprop init.svc.surfaceflinger) boot_completed=$(adb shell getprop sys.boot_completed)"
grep -h -o -E 'library "[^"]+" not found: needed by [^ ]+|CANNOT LINK EXECUTABLE.*|cannot locate symbol "[^"]+" referenced by "[^"]+"' "$OUT/logcat-after.txt" | sort | uniq -c | sort -rn | head -20
echo "logs in $OUT"
