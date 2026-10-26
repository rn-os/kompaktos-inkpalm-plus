#!/bin/zsh
# Bake the InkPalm vendor fixes into a TrebleDroid/LineageOS GSI system image (raw ext4).
#   usage: gsi/vendor-fix/bake.sh <in.img> <out.img> <libdir> [idc_file]
# - copies <in.img> to <out.img> and grows it by 64 MiB
# - adds <libdir>/*.so as /system/phh/inkpalm/lib64 (label vendor_file, root:root 0644)
# - optionally adds <idc_file> as /system/usr/idc/fts_ts.idc (label system_file)
# - optional env BOOTANIM=<zip>: replaces /system/product/media/bootanimation.zip (the dark variant
#   bootanimation-dark.zip is a symlink to it on KompaktOS, so one replacement covers both).
#   Build the zip with tools/bootanim/rescale_bootanim.py.
# - installs inkpalm-vfix.rc + inkpalm-vfix.sh: a background service (post-fs-data, permissive
#   phhsu_daemon domain) that overlays that dir over /vendor/lib64 on rk3566_eink vendors and
#   restarts the display stack.
set -eu
IN=$1; OUT=$2; LIBS=$3; IDC=${4:-}
E2=/opt/homebrew/opt/e2fsprogs/sbin
HERE=${0:A:h}
WORK=$(mktemp -d)

cp "$IN" "$OUT"
$E2/e2fsck -fy "$OUT" >/dev/null 2>&1 || true
size=$(stat -f %z "$OUT")
GROW_MB=${GROW_MB:-64}   # GROW_MB=0 when the image must stay small (e.g. a custom super)
[ "$GROW_MB" -gt 0 ] && $E2/resize2fs "$OUT" $(( (size + GROW_MB*1024*1024) / 1024 ))K >/dev/null

D() { $E2/debugfs -w -R "$1" "$OUT" >/dev/null 2>&1; }
# SELinux labels are stored NUL-terminated, like the ones Android's build tools write.
label() { printf '%s\0' "$2" > $WORK/label; D "ea_set -f $WORK/label $1 security.selinux"; }
owner() { D "set_inode_field $1 uid 0"; D "set_inode_field $1 gid 0"; }

D "mkdir /system/phh/inkpalm"; owner /system/phh/inkpalm
label /system/phh/inkpalm u:object_r:system_file:s0
D "mkdir /system/phh/inkpalm/lib64"; owner /system/phh/inkpalm/lib64
D "set_inode_field /system/phh/inkpalm/lib64 mode 040755"
# The merged /vendor/lib64 takes this dir's label, so it must stay vendor_file.
label /system/phh/inkpalm/lib64 u:object_r:vendor_file:s0
mkdir $WORK/libs; cp "$LIBS"/*.so $WORK/libs/
for f in $WORK/libs/*.so; do
  n=${f:t}; p=/system/phh/inkpalm/lib64/$n
  D "write $f $p"; owner $p
  D "set_inode_field $p mode 0100644"
  label $p u:object_r:vendor_file:s0
done

if [ -n "$IDC" ]; then
  p=/system/usr/idc/fts_ts.idc
  cp "$IDC" $WORK/idc; D "rm $p"; D "write $WORK/idc $p"; owner $p
  D "set_inode_field $p mode 0100644"
  label $p u:object_r:system_file:s0
fi

if [ -n "${BOOTANIM:-}" ]; then
  p=/system/product/media/bootanimation.zip
  cp "$BOOTANIM" $WORK/bootanimation.zip; D "rm $p"; D "write $WORK/bootanimation.zip $p"; owner $p
  D "set_inode_field $p mode 0100644"
  label $p u:object_r:system_file:s0
fi

# Gesture navigation by default (product-partition overlay config; overlay lives in
# /system/product/overlay/NavigationBarModeGestural). Skipped if the image has its own config.
if ! $E2/debugfs -R "stat /system/product/overlay/config/config.xml" "$OUT" 2>/dev/null | grep -q Inode; then
  cp "$HERE/product-overlay-config.xml" $WORK/overlay-config.xml
  D "mkdir /system/product/overlay/config"; owner /system/product/overlay/config
  D "set_inode_field /system/product/overlay/config mode 040755"
  label /system/product/overlay/config u:object_r:system_file:s0
  p=/system/product/overlay/config/config.xml
  D "write $WORK/overlay-config.xml $p"; owner $p
  D "set_inode_field $p mode 0100644"
  label $p u:object_r:system_file:s0
fi

# Short power press wakes the screen (static framework RRO, see power-wake-overlay/).
"$HERE/power-wake-overlay/build.sh" $WORK/InkPalmPowerWake.apk
p=/system/product/overlay/InkPalmPowerWake.apk
D "rm $p"; D "write $WORK/InkPalmPowerWake.apk $p"; owner $p
D "set_inode_field $p mode 0100644"
label $p u:object_r:system_file:s0
# Boot-time display fix: a background init service (never blocks boot; patching rw-system.sh,
# which init runs as a blocking exec at post-fs, hung the boot before USB came up).
p=/system/phh/inkpalm/inkpalm-vfix.sh
cp "$HERE/inkpalm-vfix.sh" "$HERE/inkpalm-vfix.rc" "$HERE/eink-bridge.sh" "$HERE/eink-apply.sh" "$HERE/inkpalm-defaults.sh" "$HERE/inkpalm-poweroff.sh" $WORK/   # debugfs args must not contain spaces
D "write $WORK/inkpalm-vfix.sh $p"; owner $p
D "set_inode_field $p gid 2000"
D "set_inode_field $p mode 0100755"
label $p u:object_r:phhsu_exec:s0          # init auto-transitions phhsu_exec -> phhsu_daemon
for n in eink-bridge.sh eink-apply.sh inkpalm-defaults.sh inkpalm-poweroff.sh; do       # e-ink bridge (phhsu_daemon, see eink-bridge.sh)
  p=/system/phh/inkpalm/$n
  D "write $WORK/$n $p"; owner $p
  D "set_inode_field $p gid 2000"
  D "set_inode_field $p mode 0100755"
  label $p u:object_r:phhsu_exec:s0
done
p=/system/etc/init/inkpalm-vfix.rc
D "write $WORK/inkpalm-vfix.rc $p"; owner $p
D "set_inode_field $p mode 0100644"
label $p u:object_r:system_file:s0

$E2/e2fsck -fn "$OUT" >/dev/null 2>&1 && echo "fsck clean" || { echo "fsck reported problems"; exit 1; }
rm -rf $WORK
echo "baked: $OUT ($(stat -f %z "$OUT") bytes)"
