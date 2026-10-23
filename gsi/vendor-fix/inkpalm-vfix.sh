#!/system/bin/sh
# Moaan InkPalm Plus display fix, helper half. init mounts the /vendor/lib64 overlay itself
# (see inkpalm-vfix.rc: it must be init's mount, or other domains can't use the files).
# This script runs in the background as phhsu_daemon: it logs the result and, if the display
# stack still is not up after a while, restarts it once. Must never block boot.
LOG=/data/misc/inkpalm-vfix.log
log() { echo "$(date +%T) $*" >> $LOG; }

if grep -q " /vendor/lib64 overlay " /proc/mounts; then
    log "overlay present: $(ls /system/phh/inkpalm/lib64 | wc -l) libs"
else
    log "overlay MISSING (init mount failed?)"
fi
log "start: composer=$(getprop init.svc.vendor.hwcomposer-2-1) sf=$(getprop init.svc.surfaceflinger)"

sleep 30
if [ "$(getprop init.svc.vendor.hwcomposer-2-1)" != running ] || [ "$(getprop init.svc.surfaceflinger)" != running ]; then
    setprop ctl.restart vendor.hwcomposer-2-1
    sleep 2
    setprop ctl.restart surfaceflinger
    log "display stack was not running; restarted composer + surfaceflinger"
fi
sleep 10
log "done: composer=$(getprop init.svc.vendor.hwcomposer-2-1) sf=$(getprop init.svc.surfaceflinger)"
