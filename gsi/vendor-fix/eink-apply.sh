#!/system/bin/sh
# Called by inotifyd as: eink-apply.sh EVENTS DIR FILE. Applies only whitelisted requests
# from InkControl's private files dir (see eink-bridge.sh):
#   eink.req : sys.eink.mode / sys.eink.one_full_mode_timeline = <digits>      (setprop)
#              persist.sys.mogu.refresh_type = 0..5, persist.vendor.fullmode_cnt (see eink-bridge.sh)
#              eink.full=1 -> one real full refresh (bumps one_full_mode_timeline, which apps
#              can't read; the HWC posts the next frame as FORCE_FULL)
#              sys.gray.gammalevel = 0..80 (HWC grey256->grey16 contrast, default 30)
#   light.req: light.cold / light.warm = 0..2047  -> /proc/aw99703{,_sec}/led_brightness
#              (InkPalm Plus frontlight: aw99703 = cold LEDs, aw99703_sec = warm LEDs;
#               those proc nodes are labelled `proc`, which apps may not write)
#   standby.req: apply=1 -> copy files/standby.png (PNG, <= 10 MB) to the vendor HWC's sleep
#              image paths /data/misc/standby{,_charge,_lowpower}.png (system:system 0644,
#              system_data_file); reset=1 -> remove them (vendor default art comes back)
#              poweroff=1 / poweroff_reset=1 -> same for files/poweroff.png -> /data/misc/
#              poweroff{,_nopower}.png (shown by the HWC at shutdown, see docs/sleep-screen.md)
#              redraw=1 -> (always-on display) only while the screen is ASLEEP and no power-off is
#              underway (/dev/inkpalm-poweroff, set by power.req): wake with the
#              frontlight held off, then sleep, so the HWC redraws the standby image just installed
#              (apply=1 in the same request is handled first). Never interrupts a user.
#              export=1 -> copy the vendor art /vendor/media/poweroff{,_nopower}.png (apps may
#              not read vendor_file) to files/vendor_poweroff{,_nopower}.png, owned by the app,
#              0600, so the app can compose its own power-off screen from the device's art
#   power.req: off=1 -> shut down (InkControl auto power-off), only if the screen is off and
#              no charger is connected right now, so a stray request can't kill a device in use
case "$3" in
    eink.req|light.req) ;;
    standby.req)
        M=/data/misc; R="$2/$3"; DIR=$2
        # install <name>: files/<name>.png -> $M/<target>.png for each further arg
        install() {
            src="$DIR/$1.png"; shift
            [ -f "$src" ] && [ ! -L "$src" ] || return 0      # no symlinks: we run as root
            [ "$(head -c 8 "$src" | xxd -p)" = 89504e470d0a1a0a ] || return 0
            [ "$(stat -c %s "$src")" -le 10485760 ] || return 0
            for n in "$@"; do
                cp "$src" $M/$n.png.tmp && chown system:system $M/$n.png.tmp &&
                    chmod 644 $M/$n.png.tmp && mv $M/$n.png.tmp $M/$n.png && restorecon $M/$n.png
            done
        }
        if grep -q '^reset=1$' "$R"; then
            rm -f $M/standby.png $M/standby_charge.png $M/standby_lowpower.png
        elif grep -q '^apply=1$' "$R"; then
            install standby standby standby_charge standby_lowpower
        fi
        if grep -q '^export=1$' "$R"; then
            u=$(stat -c %u "$DIR")
            for n in poweroff poweroff_nopower; do
                # Built outside the app's dir, then renamed in: a rename replaces whatever
                # the app put at the target (even a symlink) instead of following it.
                t=/data/local/tmp/inkpalm-export.$$
                cp /vendor/media/$n.png $t && chown $u:$u $t && chmod 600 $t &&
                    mv -f $t "$DIR/vendor_$n.png" && restorecon "$DIR/vendor_$n.png"
                rm -f $t
            done
        fi
        if grep -q '^redraw=1$' "$R" && [ -z "$(getprop sys.shutdown.requested)" ] && [ ! -e /dev/inkpalm-poweroff ] \
           && ! dumpsys power | grep -q 'mWakefulness=Awake'; then
            leds0() { echo 0 > /proc/aw99703/led_brightness; echo 0 > /proc/aw99703_sec/led_brightness; }
            input keyevent KEYCODE_WAKEUP
            i=0; while ! dumpsys power | grep -q 'mWakefulness=Awake' && [ $i -lt 10 ]; do sleep 0.5; i=$((i+1)); done
            leds0; sleep 2; leds0
            input keyevent KEYCODE_SLEEP
            sleep 2; leds0
        fi
        if grep -q '^poweroff_reset=1$' "$R"; then
            rm -f $M/poweroff.png $M/poweroff_nopower.png
        elif grep -q '^poweroff=1$' "$R"; then
            install poweroff poweroff poweroff_nopower
        fi
        exit 0 ;;
    power.req)
        grep -q '^off=1$' "$2/$3" || exit 0
        : > "$2/$3"                                       # one-shot
        [ -n "$(getprop sys.shutdown.requested)" ] && exit 0   # already shutting down (2nd app)
        dumpsys power | grep -q 'mWakefulness=Awake' && exit 0
        dumpsys battery | grep -q 'powered: true' && exit 0
        # From here on a power-off is underway: an always-on display redraw must not wake the screen
        # (InkPalm+ took the predraw's wake/sleep for the user's and re-armed its Live alarm, whose
        # redraw then woke the panel just before the shutdown, 2026-10-26). /dev is tmpfs: gone at boot.
        : > /dev/inkpalm-poweroff
        # Draw the power-off image first (wake/sleep via the HWC standby path), then shut down.
        [ -f /data/misc/poweroff.png ] && sh /system/phh/inkpalm/inkpalm-poweroff.sh predraw
        svc power shutdown || reboot -p
        exit 0 ;;
    *) exit 0 ;;
esac
while IFS='=' read -r k v; do
    case "$v" in
        ''|*[!0-9]*) continue ;;
    esac
    case "$3:$k" in
        eink.req:sys.eink.mode|eink.req:sys.eink.one_full_mode_timeline)
            setprop "$k" "$v" ;;
        eink.req:persist.sys.mogu.refresh_type)
            [ "$v" -le 5 ] && setprop "$k" "$v" ;;
        eink.req:persist.vendor.fullmode_cnt)
            [ "$v" -ge 1 ] && [ "$v" -le 1000 ] && setprop "$k" "$v" ;;
        eink.req:eink.full)
            [ "$v" = 1 ] || continue
            t=$(getprop sys.eink.one_full_mode_timeline)
            case "$t" in ''|*[!0-9]*) t=0 ;; esac
            setprop sys.eink.one_full_mode_timeline $(( (t + 1) % 1000000000 )) ;;
        eink.req:sys.gray.gammalevel)
            [ "$v" -le 80 ] && setprop "$k" "$v" ;;
        light.req:light.cold|light.req:light.warm)
            [ "$v" -le 2047 ] || continue
            if [ "$k" = light.cold ]; then f=/proc/aw99703/led_brightness
            else f=/proc/aw99703_sec/led_brightness; fi
            echo "$v" > "$f" ;;
    esac
done < "$2/$3"
