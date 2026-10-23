# run_diag.sh checks

Run: `tools/diag/run_diag.sh [--serial S] [--label NAME] [--no-root] [--rw]`
Compare: `tools/diag/compare.py <old>/results.json <new>/results.json [--props] [--all]` (exit 1 on regression).
Output: `~/InkPalm-Images/diag/<timestamp>[-label]/` (summary.txt, results.json, getprop.txt, logcat*.txt,
logcat-crash.txt, tombstones.txt, getevent-lp.txt, screenshot.png, dumpsys/, raw/, avc_summary.txt, missing_libs.txt).

Safety model: read-only everywhere. On stock the script never runs `adb root` and ignores `--rw`.
Root is attempted only on a GSI (`ro.gsid.image_running=1` or lineage/treble product) unless `--no-root`.
`--rw` (GSI + root only) adds idempotent write-back tests (`setprop sys.eink.mode <current>`). Wi-Fi is never connected.
Every adb call is time-limited (perl alarm, `--timeout`, default 25 s; logcat 90 s).

Status: PASS ok, FAIL broken, WARN degraded or unverifiable-but-suspicious, SKIP not applicable / not readable.

| Check id | PASS means | Guards KompaktOS feature |
|---|---|---|
| os_detect | OS classified as stock / dsu-gsi / flashed-gsi (info) | run-mode safety |
| boot_completed | `sys.boot_completed=1` | basic boot |
| boot_time | `boot_progress_enable_screen` event < 90 s (metric `boot_ms`) | boot regressions |
| svc_crashloop | no `init.svc.*=restarting`; WARN if a service exited >=3x in the log | stable HAL/services |
| lib_link | no `CANNOT LINK EXECUTABLE`/`dlopen failed` (list in missing_libs.txt) | vendor-fix libs (libskia, libheif stub...) |
| avc | no denials; WARN with count and top tuples in avc_summary.txt | sepolicy for einkservice, HWC, touch |
| display_stack | surfaceflinger + a `*hwcomposer*` service running | Moaan HWC (rk30board) driving the panel |
| display_screencap | `screencap` PNG has >1 distinct colour (not blank) | rendering path end to end |
| eink_props | `sys.eink.mode` readable (plus other `sys.eink.*`, `persist.sys.mogu.*`) | HWC e-ink mode interface |
| eink_service | binder service `eink` found (stock EinkService or `org.neoport.einkservice`) | per-app e-ink modes, refresh, InkControl |
| eink_write | (`--rw`) idempotent `setprop sys.eink.mode` accepted; else SKIP | property write path / sepolicy |
| touch_device | `fts_ts` in `getevent -lp`, with raw X/Y ranges | touchscreen |
| touch_idc | `dumpsys input` shows a ConfigurationFile (IDC) for fts_ts; WARN notes landscape raw axes vs portrait display | touch rotation/scale |
| keys | `gpio-keys` and `rk805 pwrkey` present | hardware buttons, power key |
| wifi | Wi-Fi HAL running, `cmd wifi status` enabled, scan results > 0 | Wi-Fi |
| bluetooth | Bluetooth HAL service running | Bluetooth |
| battery | `dumpsys battery` present=true with level | battery/charging, health HAL |
| light | lights HAL up and a backlight/leds `brightness` node readable | frontlight |
| sensors | sensors listed in `dumpsys sensorservice` (accel, light, prox counts) | auto-rotate, light sensor |
| audio | audioserver running and AudioFlinger has output threads | speaker/headphones |
| power_state | wakefulness and display power state parse from `dumpsys power` | screen on/off logic |
| suspend_stats | `/sys/power/suspend_stats` success count, no failures (counts only grow after a real sleep) | deep sleep / battery life |
| dsu_state | DSU running (slot, `gsi_tool status`, df); SKIP on non-DSU | DSU test setup |
| selinux | Enforcing (WARN if Permissive: bring-up only) | final image must be enforcing |
| kernel | 4.19.x kernel | kernel unchanged from stock |
| vendor_fp | vendor fingerprint equals the stock Moaan RK3566 vendor | vendor partition untouched |
| crashes | no tombstones and no FATAL/Fatal signal in crash buffer (tombstones need root) | stability |
| sleepscreen | stock: prop reported. GSI+root: a custom image file present (WARN = stock art would show) | custom sleep screen (docs/sleep-screen.md) |

Metrics in results.json (diffed by compare.py): boot_ms, avc_total, avc_enforced, cannot_link, dlopen_failed, sensor_count,
wifi_scan_results, suspend_success/fail, tombstones, battery_level, eink_mode, touch_x_max/y_max, kernel_release.

Notes: `adb root` restarts adbd (do not run while another agent is mid-command on the device).
`png_stats.py` (pure stdlib) is the screenshot blank test. Touch correctness (rotation) is not provable from dumps; do a tap test after IDC changes.
