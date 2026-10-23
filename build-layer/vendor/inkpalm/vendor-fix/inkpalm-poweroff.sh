#!/system/bin/sh
# Power-off screen, as stock Moaan did it: the vendor HWC draws /data/misc/poweroff.png
# (poweroff_nopower.png when sys.power.status=1) when the display is powered off while
# sys.power.shutdown=1. Moaan's ShutdownThread set that and powered the display off; KompaktOS
# does neither, so the panel kept its last frame. Started by inkpalm-vfix.rc when a shutdown is
# requested (power menu or auto power-off's power.req). Only acts when an image was installed
# (InkPalm+/InkControl: standby.req poweroff=1), so the Moaan default art never appears unasked.
case "$(getprop sys.shutdown.requested)" in
    0*) ;;          # 0<reason> = shutdown, 1<reason> = reboot
    *) exit 0 ;;
esac
[ -f /data/misc/poweroff.png ] || exit 0
lvl=$(dumpsys battery | sed -n 's/^ *level: //p')
if [ "${lvl:-100}" -le 5 ]; then setprop sys.power.status 1; else setprop sys.power.status 0; fi
setprop sys.power.shutdown 1
# The HWC draws the image on the display's power-off transition: asleep (auto power-off) needs
# a wake first.
if ! dumpsys power | grep -q 'mWakefulness=Awake'; then
    input keyevent KEYCODE_WAKEUP
    sleep 1
fi
input keyevent KEYCODE_SLEEP
