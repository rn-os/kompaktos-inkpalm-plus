#!/system/bin/sh
# InkPalm Plus first-boot defaults for our KompaktOS/GSI build. Runs after every boot_completed
# (inkpalm-vfix.rc, phhsu_daemon), but each block runs once: a marker per block keeps it from
# ever overriding the user's later choices, and a new block (v2, ...) still reaches devices that
# already ran the older ones. Gesture navigation is a build default via the product overlay config.
M=/data/misc/inkpalm
mkdir -p $M

if [ ! -f $M/defaults-v1 ]; then
    # Don't wake the screen on charger plug/unplug (LineageOS "Wake on plug").
    content insert --uri content://lineagesettings/global \
        --bind name:s:wake_when_plugged_or_unplugged --bind value:s:0
    # Display size tuned for the 720x1440 / 276 ppi panel (KompaktOS UI was made for ~240 on the Kompakt).
    wm density 312
    touch $M/defaults-v1
fi

# v2: stock Moaan behaviour KompaktOS lost (compared against stock snapshots, 2026-10-23).
if [ ! -f $M/defaults-v2 ]; then
    # No animations: on e-ink they only add ghosting and slow transitions (stock: all 0).
    for k in window_animation_scale transition_animation_scale animator_duration_scale; do
        settings put global $k 0
    done
    # Battery percentage next to the icon (stock showed it; LineageOS keeps its own key).
    settings put system status_bar_show_battery_percent 1
    content insert --uri content://lineagesettings/system \
        --bind name:s:status_bar_show_battery_percent --bind value:s:2
    # Heads-up pop-ups each cost an e-ink refresh.
    settings put global heads_up_notifications_enabled 0
    # Stock screen timeout (ro.rk.screenoff_time); auto power-off covers long idle.
    settings put system screen_off_timeout 60000
    # User's apps, only if already installed (a fresh install restores apps later).
    if pm path org.futo.inputmethod.latin >/dev/null 2>&1; then
        ime enable org.futo.inputmethod.latin/.LatinIME >/dev/null 2>&1
        ime set org.futo.inputmethod.latin/.LatinIME >/dev/null 2>&1
    fi
    if pm path info.plateaukao.einkbro >/dev/null 2>&1; then
        cmd role add-role-holder --user 0 android.app.role.BROWSER info.plateaukao.einkbro
    fi
    touch $M/defaults-v2
fi
