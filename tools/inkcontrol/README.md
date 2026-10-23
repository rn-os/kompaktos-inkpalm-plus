> **Retired.** InkControl has been replaced by [InkPalm+](https://github.com/rn-os/inkpalm-plus)
> (Screen & light panel, Quick Settings tiles, front light, sleep and power-off screens). It is kept
> here only as history and because `build-layer/` still references its sources. Do not install it
> next to InkPalm+: both would drive the screen. Never run on the stock firmware; written for KompaktOS.

# InkControl

Small no-root, no-flash Android app for the Moaan InkPalm Plus (rk3566, stock Android 11) that
brings KompaktOS-style e-ink controls: per-app refresh mode, full-refresh and mode Quick Settings
tiles, per-app colour inversion. Plain Views, black on white, no animations, no AndroidX.

Build: `tools/inkcontrol/build.sh` -> `build/inkcontrol.apk` (signed with `keys/inkpalm.jks`).
**Written without access to the device: nothing here has been run on hardware.** See "Unverified".

## Features
- `AppWatcherService` (accessibility service, `TYPE_WINDOW_STATE_CHANGED`, package name only, no
  content access). On foreground change it sets `sys.eink.mode` for that package (or the global
  default) and toggles inversion. SystemUI, `android`, permission controller and IME packages are ignored
  so popups/keyboards do not flip the mode.
- Tile "Full refresh": `sendOneFullFrame` equivalent. Optional alternative (checkbox in app):
  flash Full GC16 (2) for 700 ms and restore the previous mode.
- Tile "E-ink mode": cycles the global default through 7 -> 8 -> 22 -> 14 -> 12 and applies it
  immediately (subtitle shows the mode). Changing the default while an app with its own mode is in
  front applies the tile's mode to it until the next app switch.
- Per-app invert: sets `Settings.Secure.accessibility_display_inversion_enabled`. Only writes when
  the package wants it on, or to turn off an inversion InkControl itself turned on (so a manual
  global inversion is not clobbered).
- Settings activity: global default mode, test refresh button, per-app mode spinner + invert checkbox
  for every launcher app (SharedPreferences `inkcontrol`). First run seeds suggestions:
  readers (`com.onyx.kreader`, `org.koreader.launcher`, `org.neoport.neoreader`) -> 8 (GL16);
  browsers/messengers -> 14 (DU). Change as you like.

## Recovered API (from `~/InkPalm-Backup/system-ref/framework.jar` and `services.jar` via dexdump)

Binder service name `eink`, descriptor `android.os.IEinkManager` (AIDL, framework.jar classes2.dex).

| code | method | args | reply |
|---|---|---|---|
| 1 | `int init()` | - | int |
| 2 | `int kill()` | - | int |
| 3 | `int standby()` | - | int |
| 4 | `int quitStandby()` | - | int |
| 5 | `void setProperty(String key, String value)` | 2 x String | (exception only) |

`setProperty` is the only call that matters. Client class `android.os.EinkManager` is a thin wrapper:

| EinkManager method | what it really does |
|---|---|
| `setMode(String)` | `setProperty("sys.eink.mode", mode)`; `getMode()` reads `SystemProperties.get("sys.eink.mode","7")` |
| `sendOneFullFrame()` | increments a static int `num` (wraps to 1 near INT_MAX) and `setProperty("sys.eink.one_full_mode_timeline", String.valueOf(num))` |
| `setGrayMode(String)` | `setProperty("persist.sys.mogu.256gray", v)` |
| `setRefreshType(String)` | `setProperty("persist.sys.mogu.refresh_type", v)` |
| `setSystemRefreshType(String)` | `setProperty("persist.sys.mogu.system_type", v)` |
| `init/kill/standby/quitStandby` | straight passthrough (native: libandroid_servers.so) |

`EinkService.setProperty` (system_server) does `SystemProperties.set(key, value)` after a length
check (<= 91 chars). **There is no permission check anywhere in `EinkService`** (no
enforceCallingPermission, no uid test); access control is purely SELinux on the `eink` service lookup
and on whatever properties system_server may set. InkControl only uses `sys.eink.mode` and
`sys.eink.one_full_mode_timeline`. The `persist.sys.mogu.*` keys (256-gray, refresh type, system type)
are exposed through the same call but not used by the app (semantics unknown); they are an obvious
next thing to experiment with.

### Mode numbers (`EinkManager$EinkMode`, passed as decimal strings)
Names are the constants; semantic notes follow Rockchip EBC/E-Ink waveform naming and are not verified on the panel.

| value | constant | meaning (expected) |
|---|---|---|
| -1 | EPD_NULL | none |
| 0 | EPD_AUTO | driver picks |
| 1 | EPD_OVERLAY | overlay |
| 2 | EPD_FULL_GC16 | full-screen 16-gray, flashing, cleanest |
| 3 / 4 / 5 / 6 | EPD_FULL_GL16 / GLR16 / GLD16 / GCC16 | full-screen variants (GL16 = text, GLR16/GLD16 = ghost-reducing, GCC16 = colour) |
| 7 | EPD_PART_GC16 | partial 16-gray; stock default (`sys.eink.mode` currently 7) |
| 8 / 9 / 10 / 11 | EPD_PART_GL16 / GLR16 / GLD16 / GCC16 | partial variants |
| 12 | EPD_A2 | fast 2-level, ghosts |
| 13 | EPD_A2_DITHER | A2 with dithering |
| 14 | EPD_DU | fast 2-level direct update |
| 15 | EPD_DU4 | fast 4-level |
| 16 | EPD_A2_ENTER | A2 enter transition |
| 17 | EPD_RESET | panel reset |
| 22 / 23 | EPD_AUTO_DU / EPD_AUTO_DU4 | auto with DU / DU4 for fast updates |

The app exposes 0,2-15,22,23 (not 1,16,17).

## Permission / SELinux / hidden-API findings
- No Android permission is needed for `eink`; the service lookup must be allowed by SELinux.
  Established earlier: `eink_service` is allowed for `untrusted_app` (targetSdk >= 30) but denied for
  `untrusted_app_29`. The manifest therefore uses `minSdk 30` / `targetSdk 30` (verified in the built
  APK with `aapt2 dump badging`). Do not lower targetSdk.
- Whether `untrusted_app` is also allowed to *transact* (binder call) and whether system_server may
  set `sys.eink.*` from that caller is not something the framework code can tell us (the property
  write happens in system_server's domain, so it should work if the stock apps work).
- We never link the hidden `IEinkManager`; `Eink.java` fetches the IBinder and builds the Parcel by hand
  (`writeInterfaceToken("android.os.IEinkManager")`, two strings, transaction 5, `readException()`).
- `android.os.ServiceManager.getService(String)` is reached by reflection. On Android 11 it is on the
  "unsupported" greylist (not max-target-blocked), so plain reflection should work. If it fails, the app
  falls back once to the `VMRuntime.setHiddenApiExemptions({"L"})` double-reflection trick (works on
  Android 9-11, closed on later releases). The fallback is *only* executed if the plain call fails. If
  you want zero reliance on it, delete `exemptHiddenApis()` in `Eink.java`.
- Inversion needs `WRITE_SECURE_SETTINGS` (declared; signature|privileged|development, so it must be
  granted via adb).

## Install and test
```
adb install --no-incremental build/inkcontrol.apk
adb shell pm grant org.neoport.inkcontrol android.permission.WRITE_SECURE_SETTINGS
```
Then enable the accessibility service: Settings -> Accessibility -> InkControl per-app e-ink -> On
(or `adb shell settings put secure enabled_accessibility_services org.neoport.inkcontrol/.AppWatcherService` -- requires accessibility_enabled=1 -- 
safer to use the UI). Add the tiles by editing the Quick Settings
panel ("Full refresh", "E-ink mode"). Open InkControl: the status block at the top shows whether the
service is on, the secure-settings permission is granted and whether the `eink` binder is reachable.

Checks:
```
adb shell getprop sys.eink.mode                         # before/after opening a configured app
adb shell getprop sys.eink.one_full_mode_timeline       # increments on each Full refresh tap
adb shell settings get secure accessibility_display_inversion_enabled
adb logcat -s InkControl                                # failures are logged here
```

## Unverified (no device access while building)
1. That an `untrusted_app` (targetSdk 30) transact to `eink` and the resulting `SystemProperties.set`
   are permitted by SELinux. If `sys.eink.mode` does not change, check `adb logcat | grep avc` for
   `eink_service` / `property_service` denials.
2. That the vendor display layer reacts to changes of `sys.eink.mode` immediately and that a changed
   `sys.eink.one_full_mode_timeline` actually triggers a flash. Only the counter *increment* mirrors
   the stock client; the counter here is persisted in the app's prefs, so it can restart low after
   data clear or app reinstall. If the HAL ignores a value lower than the last seen one, taps will do
   nothing until the counter exceeds it; use the "flash Full GC16" checkbox as the alternative.
3. The best mode per use-case (the table of waveform meanings is by naming convention; 8 for readers
   and 14 for fast apps are guesses).
4. Accessibility service foreground detection can occasionally key on popup windows from other
   packages (not on the ignore list); the mode will then follow that window until the next switch.
5. Vector launcher icon: some launchers may not render a vector `android:icon`.
6. The hidden-API reflection path (and fallback) on this exact ROM build.
7. The mode-cycle tile/subtitle rendering on this ROM's Quick Settings.

## On-device findings (2026-10-23, verified on the InkPalm Plus)
- The `eink` binder works from a targetSdk-30 app: setting `sys.eink.mode` sticks while idle.
- Stock SystemUI forces the mode back to **7** after every app launch / screen settle:
  `RootWindowContainer.allResumedActivitiesIdle` writes Settings.Global `top_packagename`,
  then `EinkSettingsProvider.query` calls `setEinkMode("7")` (hard-coded; only a few system
  packages are exempt). InkControl therefore re-applies on every Activity window change, on
  every `top_packagename` change, and again at 0.3–6 s afterwards.
- Apps **cannot read** `sys.eink.*` (labelled `vendor_ebook_prop`), so the current mode is
  never known; modes are simply re-written. For the same reason the firmware's
  `one_full_mode_timeline` counter can't be continued, so "Full refresh" flashes mode 2
  (Full GC16) for 0.7 s and restores the previous mode.
- Overlay windows (e.g. a quick-panel service) also send window-state events; only events
  whose class resolves to an Activity are acted on (needs QUERY_ALL_PACKAGES).
- The vendor hwcomposer already auto-picks a text-optimised mode (EPD_AUTO_DU) by content.
- KOReader (F-Droid build `org.koreader.launcher.fdroid`) is seeded to mode 8.

## On a GSI (LineageOS via DSU) — verified 2026-10-23
No Moaan `eink` service exists there, but the vendor sepolicy lets `platform_app` set
`vendor_ebook_prop`. TrebleDroid/LineageOS GSIs are signed with the public AOSP test keys, so:
`PLATFORM_KEY=<dir with AOSP platform.pk8 + platform.x509.pem> tools/inkcontrol/build.sh`
builds `build/inkcontrol-platform.apk`, which runs as `u:r:platform_app` and sets
`sys.eink.*` directly (status shows "E-ink control: direct"). Verified: mode 7 -> 14 sticks.
There is no Moaan SystemUI on the GSI, so nothing resets the mode to 7 behind our back.
(The AOSP test keys are public; they are not stored in this repo.)

## KompaktOS parity (KompaktOS 1.2 on the InkPalm, bridge backend)
KompaktService (`com.kompakt.service`) drives the Kompakt's panel via `/sys/einkinfo/*`, absent here.
Its config lives in its **private** SharedPreferences `kompakt` (`eink_mode`, `per_app`,
`app_mode_<pkg>`, `invert_<pkg>`), not in Settings, so InkControl cannot read it directly. No
Settings key exists for e-ink. InkControl therefore (a) mirrors the preset names/tiles, (b) piggybacks on
the black flash overlay KompaktService shows, and (c) can read KompaktOS' per-app config if the bridge
copies the prefs file (see below).

| KompaktOS feature | InkPalm implementation | Status |
|---|---|---|
| Presets Fast / Fast, soft / Fast + dither / Text / Quality / Auto | `Presets.java`: 12 A2 / 14 DU / 13 A2-dither / 8 PART_GL16 / 7 PART_GC16 / 22 AUTO_DU, written to `sys.eink.mode` | implemented (mapping by intent, unverified on panel) |
| Gamma, brightness, contrast, dither level/type, TCON timings, temperature offset | none (no equivalent whitelisted property) | not possible |
| Auto (A2/GL16 switching) | mode 22 (vendor HWC AUTO_DU) | implemented |
| E-ink QS tile (cycles presets, then flash) | "E-ink mode" tile cycles the six presets in KompaktOS order, then Full GC16 flash | implemented |
| Six per-mode QS tiles (category "E-ink modes") | `PresetTileService$*` tiles, same labels, active = current default, flash on change | implemented |
| Refresh QS tile / long-press Home flush (black overlay 480 ms) | InkControl's "Full refresh" tile (mode 2 flash 0.7 s) plus: when the accessibility service sees KompaktService's overlay (`com.kompakt.service`, class `android.view.View`) it does the same real mode-2 flash (option "Full flash when KompaktOS refreshes", debounced 2 s) | implemented |
| Per-app mode (`EinkAppWatcher`, skip if unchanged) | `AppWatcherService`; writes skipped when unchanged on non-stock backends (re-apply storm only on stock Moaan firmware) | implemented |
| Per-app mode from KompaktOS' own config | `KompaktSync` parses `files/kompakt_prefs.xml` (copy of KompaktService's `kompakt.xml`); app mode > master; `per_app=false` honoured; a changed KompaktOS master is adopted as default | needs bridge change (file copy) |
| Per-app invert (`AppInvert`) | When synced, InkControl leaves invert to KompaktService (same Secure setting; one owner). Not synced: InkControl's own invert list works; do not configure both. | implemented |
| Full refresh every N partials | KompaktService does not do this (on demand only); stock `persist.vendor.fullmode_cnt` still applies | n/a |
| Unlock flush, `UNLOCKED` broadcast, AOD, sleep image | KompaktService source has no e-ink action on unlock; panel is bistable; `/sys/einkinfo/sleep_image` absent | not possible / n/a |
| `/sys/einkinfo/clear` | replaced by the mode-2 flash | implemented |

### Needs bridge change (optional; the baked boot fixes were not edited here)
1. Config sync: on each `eink.req` write (ideally also an inotifyd watch), copy
   `/data/data/com.kompakt.service/shared_prefs/kompakt.xml` to
   `/data/data/org.neoport.inkcontrol/files/kompakt_prefs.xml`, chown to InkControl's uid, chmod 600,
   restorecon. Fixed path pair, read-only on the source.
2. Optional experiment, not used by the app: allow `persist.sys.mogu.256gray` values `0`/`1`.
Everything else works with the existing two-key whitelist.

### On-device test plan
1. Install `build/inkcontrol.apk`, enable the accessibility service, add the QS tiles (six presets, "E-ink mode", "Full refresh"). Status block should say "InkPalm bridge (GSI)".
2. Tap each preset tile: one flash each; as root `getprop sys.eink.mode` shows 12, 14, 13, 8, 7, 22 for Fast, Soft, Fast+dither, Text, Quality, Auto. Scroll a web page in each and judge.
3. Give an app its own mode in InkControl; mode changes on app switch and nothing is re-written while staying in the app (no extra flashes).
4. Tap KompaktOS' Refresh tile or long-press Home: black overlay then a real full flash (mode 2, restored). Untick "Full flash when KompaktOS refreshes" to confirm it stops.
5. After the bridge change: set an app to Text in KompaktOS Settings, switch to it; InkControl applies 8 and shows "synced". Turn off KompaktOS per-app: all apps use the default.
6. Invert for an app in KompaktOS only: exactly one owner toggles it.
7. Switch between two same-mode apps ten times: no flicker.

## Frontlight API (for other apps, e.g. the inkpalm+ side panel)
InkControl stays the only thing driving the LEDs; other apps read/set through:
- **Read:** `content://org.neoport.inkcontrol.light/state` → one row: `supported` (0/1),
  `cold`, `warm` (0–100), `cold_on`, `warm_on`, `follow_system` (0/1). The provider notifies
  on that URI, and `org.neoport.inkcontrol.action.LIGHT_CHANGED` is broadcast on every change.
- **Set:** explicit broadcast `org.neoport.inkcontrol.action.SET_LIGHT` to package
  `org.neoport.inkcontrol` (component `.LightApi$Receiver`), optional extras `cold`, `warm`
  (int 0–100), `cold_on`, `warm_on` (boolean).
- Clients on Android 11+ need `<queries><package android:name="org.neoport.inkcontrol"/></queries>`.
- Note: the receiver and provider are exported **without a permission**, so any installed app can
  read or change the light (levels 0–100 and on/off only; nothing else is reachable through them).
- Test: `adb shell content query --uri content://org.neoport.inkcontrol.light/state`;
  `adb shell am broadcast -n 'org.neoport.inkcontrol/.LightApi$Receiver' -a org.neoport.inkcontrol.action.SET_LIGHT --ei warm 60`
