# InkPalm e-ink backend for a LineageOS GSI

Offline design + code. Nothing here was built or run; "UNVERIFIED" marks guesses. Sources: KompaktOS
`vendor/kompakt/KompaktService` (read via gh), stock `~/InkPalm-Backup/system-ref/*` (dexdump, and a disassembly of
`libandroid_servers.so`), `tools/inkcontrol/README.md`, `docs/gsi-scoping.md`.

Layout: `src/org/neoport/einkservice/*.java` (app), `Android.bp`, `AndroidManifest.xml`, `einkservice.rc`,
`privapp-permissions-*.xml`, `initial-package-state_*.xml`, `sepolicy/{einkservice.te,property_contexts}`, `res/`.

## 1. What stock did that a GSI loses (recovered)

| Stock component | What it does | Replacement here |
|---|---|---|
| `EinkService` (system_server, binder `eink`) | `setProperty(k,v)` = `SystemProperties.set` (len <= 91). Nothing else in Java. | `RkEinkBackend` sets props (relay or direct) |
| `EinkManager` wrapper | setMode -> `sys.eink.mode`; sendOneFullFrame -> bump `sys.eink.one_full_mode_timeline`; setRefreshType -> `persist.sys.mogu.refresh_type`; setSystemRefreshType -> `persist.sys.mogu.system_type`; setGrayMode -> `persist.sys.mogu.256gray` | same props, `RkEinkBackend` constants |
| SystemUI `EinkSettingsProvider.query` (fires on every top-package change via Settings.Global `top_packagename`) | per app: `setEinkMode("7")` (hard-coded, both branches), `persist.sys.mogu.refresh_type` = app refresh_mode (default 0), `persist.vendor.fullmode_cnt` = app refresh_frequency (default **40**), `persist.sys.mogu.system_type` = "1" for `com.moan.{cloudservices,appstore,sdmanage,launcher.epd305}` and `com.android.calculator2`, else "0"; if contrast set: `debug.sf.gamma.gamma` = table[gain] (15 floats 1.5 ... 0.1, default gain index 9 = 0.6) | `applyBootDefaults` + `EinkPrefs` rk_* keys. Per-app gain/dpi/bleach (`com.rockchip.eink.appcustom` provider, `app_bleach_filter`, `setAppDpiToMap`) NOT ported |
| `libandroid_servers.so` natives (disassembled) | `init()` = `ctl.start einkdrawpath`; `kill()` = `ctl.stop einkdrawpath`; `standby()` = `ctl.start standby`; `quitStandby()` = `ctl.stop standby`. Return 0. | opt-in relay in `einkservice.rc` (section 4) |
| `android.os.MoanWallPaper` (framework.jar) | `persist.sys.mogu.wallpaper` / `persist.sys.mogu.shutdown_wallpaper` = path of PNGs under `data/mogu/`; also `goToSleep`/`wakeUp` helpers | Probably the sleep/shutdown image the vendor side draws (UNVERIFIED). Not ported; see open question 6 |

Key finding: **no Java caller of `init/kill/standby/quitStandby` exists** in services.jar, SystemUI, MoanLauncher or EinkLaunchRecent.
They are only reachable through the binder; callers (if any) are in apps outside the backed-up set. So stock does not
visibly start/stop `einkdrawpath`/`standby` on screen off from the framework; vendor init presumably starts
`einkdrawpath` itself (UNVERIFIED, check `init.svc.einkdrawpath`).

## 2. KompaktService feature -> Kompakt backend -> Rockchip equivalent

| Feature (KompaktService file) | Kompakt backend call | Rockchip equivalent / status |
|---|---|---|
| 6 refresh presets fast/soft/fastdither/text/quality/auto (`Eink.MODES`, `Eink.setMode`) | `/sys/einkinfo/{waveform_mode,pixelbits,gamma,brightness,contrast,dither_type,dither_param,timings_mode}` | `sys.eink.mode` int: fast=12 A2, fastdither=13 A2_DITHER, soft=14 DU, text=8 PART_GL16, quality=7 PART_GC16 (stock default), auto=22 AUTO_DU. Mapping by intent, UNVERIFIED. No brightness/contrast/dither/timings dials; optional `debug.sf.gamma.gamma` |
| Per-app mode (`EinkAppWatcher`, AccessibilityService) | `Eink.setMode(prefs.appMode(pkg))`, skip if unchanged | `ForegroundTracker` (task stack listener) -> `EinkController.onForeground`. Accessibility avoided (needs enabling, Safety Center). Unchanged-mode skip kept |
| Global default + master mode tile (`Prefs.mode`, `EinkTileService`) | same | `Tiles$ModeTile` cycles `EinkModes`; `SET_MODE` broadcast |
| Per-mode tiles + tile-editor group (`Eink*TileService`, frameworks_base 0108) | same | Not ported (needs patch 0108). One cycling tile only |
| Manual refresh / long-press home (`RefreshReceiver`, `Flash`, patches 0016/0035) | `Flash` black overlay 480 ms; some paths `/sys/einkinfo/clear` | Default: bump `sys.eink.one_full_mode_timeline` (real full frame). Fallbacks: `mode2` (Full GC16 for 700 ms, from InkControl, verified there) and `overlay` (Flash.java port). Receiver action `org.neoport.einkservice.action.REFRESH`; retarget framework patch 0016/0035 (they send `com.kompakt.service.action.REFRESH`) |
| Refresh after unlock (`UnlockRefresh`, patch 0043 sends `...UNLOCKED`) | `Flash.show` after 150 ms | `ACTION_USER_PRESENT`/`SCREEN_ON` receiver -> `fullRefresh()` after 150 ms. No framework patch needed |
| Lock flash (`LockFlash`, `meink_hal deghost_every`) | module param | No equivalent. Full refresh at screen on instead |
| Sleep image (`SleepImage`, `/sys/einkinfo/sleep_image`) | sysfs | Not ported; maybe `persist.sys.mogu.shutdown_wallpaper` (open question 6) |
| AOD (frameworks_base 0004/0028-0031/0036/0048/0056/0062/0063) | `eink_aod_func`, kernel | Not applicable; no AOD on RK EBC path known. Skip |
| Per-app invert (`AppInvert`) | `Settings.Secure.accessibility_display_inversion_enabled` | Ported verbatim (`AppInvert.java`), runs as system uid with WRITE_SECURE_SETTINGS |
| Temperature offset (`eink_temperature`) | sysfs | None. Vendor/kernel reads panel temp itself (UNVERIFIED) |
| Torch, LED, buttons, SIM, link service, battery, offline switch | Mudita hardware | Out of scope |
| Settings UI (per-app spinners) | prefs | Not ported yet. Use `am broadcast` (see `EinkReceiver` javadoc). A small Activity is the next step |

Backend seam: `EinkBackend` (`applyBootDefaults/applyMode/fullRefresh/onScreenState`), implementations
`RkEinkBackend`, `KompaktSysfsBackend` (presets copied from `Hardware.kt`), chosen by `EinkBackends.select()`.

## 3. What the stock firmware did implicitly and the GSI must reproduce

1. **Boot defaults.** Nothing writes `sys.eink.mode` etc. unless something does. `einkservice.rc` sets mode 7 at
   `early-boot`; the app (`applyBootDefaults`, persistent + directBootAware, device-protected prefs) writes mode,
   refresh_type 0, system_type 0, fullmode_cnt 40 at start and again at BOOT_COMPLETED. Check first whether vendor init already seeds
   these (open question 1); if so drop the rc defaults to avoid fighting persist values.
2. **Re-assert mode on app switch.** Stock re-wrote 7 on each top-package change; the GSI writes the per-app mode on the
   same event. The vendor HWC may also reset `sys.eink.mode` itself (InkControl saw only SystemUI doing it). `reapply()` runs on screen on.
3. **Full refresh after wake/unlock.** Stock: user taps refresh. Here: automatic (pref `unlock_refresh`, default true).
4. **Screen off / standby.** Unknown semantics of `standby` and `einkdrawpath` services (section 4). Default = do nothing,
   because on stock the framework does not call them. Panel hold-image at suspend is normally the EBC driver's job.
5. **Property write path.** Apps cannot read `sys.eink.*` (vendor_ebook_prop); so the service keeps its own state and re-writes.
6. **Properties persisted by stock**: `persist.sys.mogu.*`, `persist.vendor.fullmode_cnt` live in /data/property. A GSI flash that keeps /data keeps them.

### Property write: relay vs direct
Relay (default): app sets `sys.inkpalm.<name>`, init trigger runs `setprop <real> ${sys.inkpalm.<name>}`
(`einkservice.rc`). Needs only new platform types. Direct (`persist.sys.inkpalm.eink_direct=1`): app sets the vendor
prop itself; needs `set_prop(system_app, vendor_ebook_prop)`, which cannot be written in system_ext policy (type defined in
vendor policy; AOSP also has coredomain-vs-vendor-prop neverallows, which one is UNVERIFIED). Relay costs one property
round trip and works with a stock vendor sepolicy unchanged. Caveat: `on property:x=*` fires per set; whether re-setting
an identical value re-fires is UNVERIFIED, hence `full_frame` is a strictly increasing counter.

## 4. Vendor services `einkdrawpath` and `standby`

Facts: libandroid_servers natives only do `ctl.start/ctl.stop` on these two service names (disassembled; strings at
0x350ca `einkdrawpath`, 0x34710 `standby`). Guess (UNVERIFIED): `einkdrawpath` is the vendor daemon feeding the draw path /
sleep wallpaper for EBC, `standby` handles panel standby/sleep image. Because `ctl.start` from system_app is blocked by
sepolicy (ctl_start_prop neverallow outside system_server/init set), we use init rc `start`/`stop` driven by
`sys.inkpalm.standby` / `sys.inkpalm.drawpath`, gated by `persist.sys.inkpalm.standby_relay=1` and app pref `standby_relay`.
Both off by default. Does init in /system_ext may `start` a service defined in /vendor? Treble allows it at runtime (single
service namespace); UNVERIFIED for these services (could be `disabled`, `oneshot`, or absent in the vendor rc).

## 5. sepolicy (`sepolicy/`)

* `property_contexts`: `sys.inkpalm.` -> `inkpalm_prop`, `persist.sys.inkpalm.` -> `inkpalm_persist_prop`.
* `einkservice.te`: declare both types; `set_prop/get_prop(system_app, inkpalm_prop)`; shell can set the opt-in flag. init needs nothing.
* The app is a platform-signed `android.uid.system` priv-app, so it runs as `system_app`. Everything else it does (task stack
  listener, overlay window, tile service, Settings.Secure) is the same Binder surface KompaktService already used in that domain.
* Vendor type name: `vendor_ebook_prop` (from the stock vendor `vendor_property_contexts`; confirm which keys carry it). Direct path
  rule is included commented out in `einkservice.te`.
* Wire in with `BOARD_SYSTEM_EXT_PRIVATE_SEPOLICY_DIRS += vendor/inkpalm/einkservice/sepolicy` (and
  `SYSTEM_EXT_PRIVATE_SEPOLICY_DIRS` on newer trees); property_contexts goes in the same dir as `property_contexts`. TrebleDroid/phh note: the GSI always
  recompiles policy at boot (see docs/gsi-scoping.md 0002 roletype issue), so our types are merged with the stock vendor CIL.
* No file_contexts needed (no sysfs access in the Rockchip backend).

## 6. Open questions: concrete checks once the GSI boots

1. `adb shell getprop | grep -E 'eink|mogu|fullmode|gamma'` on a fresh boot with the service disabled (`pm disable org.neoport.einkservice`): do vendor init scripts seed `sys.eink.mode` (and which value)?
2. `adb logcat -b all | grep -E 'avc|InkPalmEink'` after toggling a tile: any `denied { set }` for `sys.inkpalm.*`; then `adb shell getprop sys.inkpalm.eink_mode` vs `getprop sys.eink.mode` (relay worked?). Also `adb logcat -s init | grep inkpalm`.
3. `adb shell getprop init.svc.einkdrawpath; getprop init.svc.standby` and `adb shell grep -rn -E 'einkdrawpath|standby' /vendor/etc/init/` (names, class, disabled/oneshot, who starts them).
4. Panel really changes: `adb shell setprop sys.eink.mode 14` vs 7 while scrolling; confirm the mode-name mapping (text should be crisp at 8, A2 fast at 12) and that EPD_AUTO_DU (22) does not conflict with HWC auto-selection.
5. `adb shell setprop sys.eink.one_full_mode_timeline 12345` (increasing) causes a full flash; does an identical or lower value do nothing (counter semantics)?
6. Sleep image: `adb shell ls -l /data/mogu/; getprop persist.sys.mogu.wallpaper persist.sys.mogu.shutdown_wallpaper`; screen off/on: does the panel retain the last frame, show a vendor wallpaper, or go blank? Only if blank, enable `standby_relay` and compare.
7. `adb shell dumpsys activity activities | grep -i taskstack` and `adb logcat -s InkPalmEink`: "task stack listener registered" present, and per-app mode writes on app switch. If registration fails (hidden API), switch `ForegroundTracker` to an AccessibilityService as in Kompakt.
8. `adb shell dumpsys package org.neoport.einkservice | grep -E 'uid|persistent|granted'`: priv-app permissions granted (no `privapp-permissions` allowlist error in `adb logcat -s PackageManager`), `adb shell dumpsys activity processes | grep einkservice`: running at boot, domain `ps -AZ | grep einkservice` = `u:r:system_app:s0`.
9. Does SurfaceFlinger honour `debug.sf.gamma.gamma` on the GSI (`getprop` after setting `rk_gamma` via `SET_PREF`), or does it need the stock `libgralloc`/HWC flag `persist.vendor.hwc.contrast_key`?

## 7. Risks

* Blank/white panel at boot if the vendor HWC needs framework pieces beyond `sys.eink.*` (e.g. `eink` binder lookup, MoanLauncher-only props): the code cannot fix that; fallback is a minimal `IEinkManager` binder (AIDL in InkControl README).
* Hidden API drift (Android 14 -> 16): `SystemProperties.set`, `ActivityTaskManager.getService().registerTaskStackListener`, `TaskStackListener` signature; MANAGE_ACTIVITY_TASKS must be in the priv-app allowlist or the package fails to boot ("Privileged permission not in allowlist").
* sepolicy: type `system_app` assumption, `system_ext` private policy mechanics and neverallow checks unverified; a bad policy bootloops rather than failing softly (GSI recompile).
* Wrong mode mapping or fullmode_cnt/refresh_type semantics could cause ghosting or excessive flashing; mode ids are from framework constants, not panel testing.
* `standby_relay` could blank the panel if `standby` means something other than assumed; off by default.
* Fixed `persist.vendor.fullmode_cnt=40` etc. are rewritten at each boot and override user changes made elsewhere.
