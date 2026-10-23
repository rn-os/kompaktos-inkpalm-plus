#!/bin/zsh
# Live display-fix loop for the LineageOS DSU *test boot only*.
# Adds stock Android 11 libraries (from ~/InkPalm-Images/stock-libs/merged64) to a RAM-backed
# overlay over /vendor/lib64, then restarts the vendor composer + SurfaceFlinger and reports
# the next missing library / symbol / crash. Nothing is written to any partition; the overlay,
# the RAM folder and the permissive SELinux mode all disappear on the next reboot (-> stock).
#   usage: tools/dsu_tryfix.sh [--reset] [lib.so | /path/to/lib.so ...]
#   --reset empties the overlay first (local bundle, /data/local/tmp copy and RAM folder)
#   --from-system: instead, overlay the libs baked into the image (/system/phh/inkpalm/lib64)
#                  exactly like the boot hook does, to test the hook's mount after boot
set -u
L=$HOME/InkPalm-Images/stock-libs

# Guard: refuse on stock (system fingerprint contains rockchip/Moaan) or anything not a GSI.
# ro.product.name is spoofed by phh on the GSI, so it is NOT used (see tools/lib/inkpalm_os.sh).
. "${0:A:h}/lib/inkpalm_os.sh"
ip_require_gsi
ip_root_or_die
if [ "$(adb shell getenforce | tr -d '\r')" != Permissive ]; then adb shell setenforce 0; fi
adb shell 'mountpoint -q /mnt/vlib || { mkdir -p /mnt/vlib && mount -t tmpfs -o size=64m,mode=0755 tmpfs /mnt/vlib; }'

if [ "${1:-}" = --from-system ]; then
  adb shell 'while grep -q " /vendor/lib64 overlay " /proc/mounts; do umount -l /vendor/lib64 || break; done; mount -t overlay overlay -o ro,lowerdir=/system/phh/inkpalm/lib64:/vendor/lib64 /vendor/lib64 && echo "overlay from /system: $(ls /system/phh/inkpalm/lib64 | wc -l) libs"; ls -lZ /vendor/lib64/libskia.so'
  adb logcat -c
  adb shell 'setprop ctl.restart vendor.hwcomposer-2-1; sleep 2; setprop ctl.restart surfaceflinger'
  sleep 25
  echo "composer=$(adb shell getprop init.svc.vendor.hwcomposer-2-1) sf=$(adb shell getprop init.svc.surfaceflinger) boot_completed=$(adb shell getprop sys.boot_completed)"
  adb logcat -d -b all | grep -o -E 'library "[^"]+" not found: needed by [^ ]+|cannot locate symbol "[^"]+" referenced by "[^"]+"|CANNOT LINK.*|Fatal signal [0-9]+ \([A-Z]+\)' | sort | uniq -c | head
  exit 0
fi
if [ "${1:-}" = --reset ]; then
  shift; rm -rf $L/vlib64
  adb shell 'rm -rf /mnt/vlib/* /data/local/tmp/vlib64'
fi
mkdir -p $L/vlib64
for l in "$@"; do
  case $l in /*) cp "$l" $L/vlib64/ ;; *) cp $L/merged64/$l $L/vlib64/ ;; esac || exit 1
done
adb push $L/vlib64/. /data/local/tmp/vlib64/ >/dev/null
adb shell 'cp /data/local/tmp/vlib64/* /mnt/vlib/ && chmod 644 /mnt/vlib/*'
# Overlay layers must not change while mounted: remount to pick up new files.
adb shell 'while grep -q " /vendor/lib64 overlay " /proc/mounts; do umount -l /vendor/lib64 || break; done; mount -t overlay overlay -o lowerdir=/mnt/vlib:/vendor/lib64 /vendor/lib64 && echo "overlay: $(ls /mnt/vlib | wc -l) libs"'

adb logcat -c
adb shell 'setprop ctl.restart vendor.hwcomposer-2-1; sleep 2; setprop ctl.restart surfaceflinger'
sleep 25
echo "composer=$(adb shell getprop init.svc.vendor.hwcomposer-2-1) sf=$(adb shell getprop init.svc.surfaceflinger) boot_completed=$(adb shell getprop sys.boot_completed)"
adb logcat -d -b all | grep -o -E 'library "[^"]+" not found: needed by [^ ]+|cannot locate symbol "[^"]+" referenced by "[^"]+"|CANNOT LINK.*|Fatal signal [0-9]+ \([A-Z]+\)|Abort message: .*' | sort | uniq -c | head
