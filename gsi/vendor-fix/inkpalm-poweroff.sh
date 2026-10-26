#!/system/bin/sh
# Power-off screen: /data/misc/poweroff.png (poweroff_nopower.png at <=5% battery) drawn by the
# vendor HWC on a final display power-off, so the panel keeps it after shutdown (KompaktOS
# otherwise leaves the last frame). Started by inkpalm-vfix.rc when a shutdown is
# requested (power menu or auto power-off's power.req). Only acts when an image was installed
# (InkPalm+/InkControl: standby.req poweroff=1), so the Moaan default art never appears unasked.
# `predraw`: called by the bridge (auto power-off) BEFORE it requests the shutdown, so the image
# is fully drawn first and nothing races the ~10 s shutdown. Otherwise: init, on shutdown.
PRE=0; [ "$1" = predraw ] && PRE=1
if [ $PRE = 0 ]; then
case "$(getprop sys.shutdown.requested)" in
    0*) ;;          # 0<reason> = shutdown, 1<reason> = reboot
    *) exit 0 ;;
esac
fi
[ -f /data/misc/poweroff.png ] || exit 0
L=/data/misc/inkpalm/poweroff.log
w() { dumpsys power | sed -n 's/.*mWakefulness=//p' | head -1; }
log() { echo "$(date '+%F %T') $* [$(w)]" >> $L; }
[ $PRE = 1 ] && : > $L
log "start (pre=$PRE req=$(getprop sys.shutdown.requested))"
# Already drawn by `predraw` and still asleep: nothing to redo.
if [ $PRE = 0 ] && [ -n "$(getprop persist.sys.mogu.wallpaper)" ] && ! dumpsys power | grep -q 'mWakefulness=Awake'; then
    log "predrawn, skipping"
    sleep 60; log "safety net: forcing power-off"; setprop sys.powerctl shutdown; exit 0
fi
lvl=$(dumpsys battery | sed -n 's/^ *level: //p')
img=/data/misc/poweroff.png
[ "${lvl:-100}" -le 5 ] && [ -f /data/misc/poweroff_nopower.png ] && img=/data/misc/poweroff_nopower.png
# Draw it through the HWC's normal STANDBY path: every standby branch first draws
# persist.sys.mogu.wallpaper if readable (hwcomposer 0x115b8/0x1163c/0x1173c) and sends the
# frame as EPD_SUSPEND (18). The HWC's own shutdown path (sys.power.shutdown=1) sends
# EPD_POWER_OFF (20) instead, on which the kernel's ebc_thread exits for good: any later wake
# then blocks the composer in EBC_GET_BUFFER and system_server watchdog-loops until a reboot
# (2026-10-25 investigation). The HWC reads the prop only at the power-off transition.
setprop persist.sys.mogu.wallpaper "$img"
log "wallpaper=$img"
# Auto power-off starts asleep: wake (safe on this path), let the slow e-ink finish drawing,
# then one SLEEP (one retry if it didn't take) so the HWC draws the image.
awake() { dumpsys power | grep -q 'mWakefulness=Awake'; }
if ! awake; then
    input keyevent KEYCODE_WAKEUP
    i=0; while ! awake && [ $i -lt 10 ]; do sleep 0.5; i=$((i+1)); done
    # inkpalm+ restores the frontlight at screen-on: keep it dark for the shutdown.
    echo 0 > /proc/aw99703/led_brightness; echo 0 > /proc/aw99703_sec/led_brightness
    sleep 2
    log "woke"
fi
input keyevent KEYCODE_SLEEP
sleep 3
log "sleep 1"
awake && { input keyevent KEYCODE_SLEEP; sleep 3; log "sleep 2"; }
[ $PRE = 1 ] && { sleep 2; log "predraw done"; exit 0; }   # e-ink waveform finishing
# The prop stays set until boot (inkpalm-vfix.rc clears it). The system's own shutdown powers the
# display off once more and that transition draws the image too: a shutdown can finish in ~10 s,
# before the SLEEP above lands (2026-10-25 live test).
# Safety net: still running 60 s later means the shutdown stalled (a lost display transition,
# or a driver hang after the final draw): force it. Kept in the foreground, since init kills a
# service's leftover processes when its main process exits; on a normal shutdown init kills us
# long before this.
sleep 60
log "safety net: forcing power-off"
setprop sys.powerctl shutdown
