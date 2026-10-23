#!/system/bin/sh
# InkPalm e-ink bridge for GSIs whose platform key we don't have (e.g. MisterZtr release-keys
# builds): InkControl writes "key=value" lines to its private files/eink.req; this root helper
# (phhsu_daemon, started from inkpalm-vfix.rc) applies them with setprop. eink-apply.sh only
# accepts the e-ink properties with numeric values. Not needed where InkControl can set the
# properties itself (stock binder, or a platform-signed build on a test-keys GSI).
# Watched apps: InkControl, and InkPalm+ (which is absorbing InkControl), so the merged app
# needs no new image. Each gets its own watch loop; requests are applied per directory.
APPS="org.neoport.inkcontrol com.inkpalmplus"
# Vendor HWC (ReassessmentEpdMode) only honours sys.eink.mode with
# persist.sys.mogu.refresh_type=0 and system_type=0 (unset on KompaktOS = 0; 1/2/4+ re-pick by
# content, 3 = always PART_GLR16). persist.vendor.fullmode_cnt is the kernel's full refresh
# every N partial updates: driver default 500 is effectively never, stock Moaan ran 40.
# Seeded only when unset, so a later choice sticks.
[ -n "$(getprop persist.vendor.fullmode_cnt)" ] || setprop persist.vendor.fullmode_cnt 40
watch_app() {
    D=/data/data/$1/files
    while true; do
        while [ ! -d $D ]; do sleep 5; done
        # w = closed after writing. inotifyd exits if the dir goes away (app reinstalled).
        inotifyd /system/phh/inkpalm/eink-apply.sh "$D:w"
        sleep 2
    done
}
for a in $APPS; do watch_app $a & done
wait
