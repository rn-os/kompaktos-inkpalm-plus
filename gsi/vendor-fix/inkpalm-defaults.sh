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

# v3: apps that don't fit a WiFi-only e-ink device (no modem, SIM, camera or FM). Removed for
# user 0 only: reversible with `cmd package install-existing <pkg>`. Verified 2026-10-25 (reboot,
# Settings ▸ Network, Kompakt tiles fine). Keep: com.kompakt.service (e-ink tiles, refresh flash,
# per-app config), com.android.phone / telecom / telephony + contacts providers, carrierconfig.
if [ ! -f $M/defaults-v3 ]; then
    for p in com.android.dialer com.android.dialer.auto_generated_rro_product__ \
             com.android.messaging org.lineageos.aperture org.lineageos.aperture.frameworksbaseoverlay \
             com.google.android.apps.googlecamera.fishfood com.android.cameraextensions \
             com.android.fmradio com.android.fmradio.recordings me.phh.qcrilam com.android.stk \
             im.angry.openeuicc com.android.simappdialog com.android.carrierdefaultapp \
             com.android.imsserviceentitlement com.android.ons com.android.telephony.qns \
             com.google.android.iwlan com.android.cellbroadcastreceiver com.android.smspush \
             com.android.calllogbackup com.android.emergency com.android.se \
             me.phh.treble.overlay.mtkims_telephony me.phh.treble.overlay.flossims_telephony \
             me.phh.treble.overlay.cafims_telephony me.phh.treble.overlay.hwims_telephony \
             me.phh.treble.overlay.slsiims_telephony me.phh.treble.overlay.sprdims_telephony; do
        pm uninstall -k --user 0 $p >/dev/null 2>&1
    done
    # The Kompakt app's own screen (Mudita settings, incl. the "Smallest width" row that broke
    # the density); its service and tiles stay.
    pm disable --user 0 com.kompakt.service/com.kompakt.service.KompaktActivity >/dev/null 2>&1
    touch $M/defaults-v3
fi

# v4: InkPalm+ always-on display updates every few minutes while asleep; Doze otherwise limits
# its allow-while-idle alarms to about one per 9 min. Persisted by deviceidle.
if [ ! -f $M/defaults-v4 ]; then
    pm path com.inkpalmplus >/dev/null 2>&1 && cmd deviceidle whitelist +com.inkpalmplus >/dev/null 2>&1
    touch $M/defaults-v4
fi

# v5: the GSI declares NFC but the panel has no NFC chip or HAL, so com.android.nfc fails to start
# every ~15 s while awake and on each always-on display wake (ANR "failed to complete startup",
# 2026-10-29). Removed for user 0 like v3. Logs kept across reboots (16 x 1 MB, /data/misc/logd)
# so a freeze or crash leaves a trace: `adb root; adb pull /data/misc/logd`.
if [ ! -f $M/defaults-v5 ]; then
    pm uninstall -k --user 0 com.android.nfc >/dev/null 2>&1
    setprop persist.logd.logpersistd.size 16
    setprop persist.logd.logpersistd.buffer main,system,crash,events,kernel
    setprop persist.logd.logpersistd logcatd
    touch $M/defaults-v5
fi
