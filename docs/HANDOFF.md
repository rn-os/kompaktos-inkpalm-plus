> Maintainer's working log, kept as a record of what was tried and measured. Paths like `~/InkPalm-Backup`
> and `~/InkPalm-Images` are folders on the author's Mac; make your own (see the README).
> InkControl, mentioned below, has been replaced by InkPalm+.

# Handoff — InkPalm Plus running KompaktOS (2026-10-23)

## Device state (daily driver)
- Moaan InkPalm Plus (rk3566, e-ink 720x1440, 276 ppi, Android 11 vendor, kernel 4.19).
- **Flashed KompaktOS 1.2 Global Vanilla (LineageOS 23.2 / Android 16)** on slot B via a custom
  `super` (tools/build_super.py): system_b = KompaktOS + our fixes; system_ext/vendor/product/odm_b
  = stock. Slot A empty. Stock boot_b/vbmeta/dtbo untouched. SELinux enforcing.
- User data restored (37 apps, all of /sdcard). microG 0.3.17 (GmsCore + Companion) installed as
  user apps — KompaktOS's framework has LineageOS restricted signature spoofing for the official
  microG cert. User may still need to finish microG Self-Check.
- Runtime settings applied: density 312, gesture navigation, wake-on-plug off (user did it).
- adb root is disabled on the device (developer setting); `tools/dsu_tryfix.sh` & backup scripts
  need root.

## Our fixes (gsi/vendor-fix/, baked by gsi/vendor-fix/bake.sh)
- Display: vendor `hwcomposer.rk30board.so` needs stock A11 `libskia.so` (+ libdng_sdk, libft2,
  libandroidicu, libicuuc, libicui18n, and a **stub libheif** from heif_stub.c). They live in
  `/system/phh/inkpalm/lib64` and **init** overlays them on `/vendor/lib64` at post-fs-data
  (`inkpalm-vfix.rc`). Must be init's mount (a phhsu_daemon mount caused fd-use denials).
- Touch: `fts_ts.idc` ORIENTATION_270.
- Root bridge (`eink-bridge.sh` + `eink-apply.sh`, phhsu_daemon, inotifyd on InkControl's files
  dir): whitelisted `eink.req` (sys.eink.mode / one_full_mode_timeline), `light.req`
  (cold/warm 0..2047 → /proc/aw99703{,_sec}/led_brightness; aw99703 = cold, _sec = warm),
  `standby.req` (sleep image → /data/misc/standby*.png; rejects symlinks/non-PNG).
- Gesture nav default: `/system/product/overlay/config/config.xml`.
- First-boot defaults once (`inkpalm-defaults.sh`): wake-on-plug off, density 312.
- Boot animation rescaled to 720x1440 (`BOOTANIM=` in bake.sh; tools/bootanim/).
- **Pending flash:** `~/InkPalm-Images/kompaktos/baked/system-vanilla-next.img` contains all the
  above incl. gesture default, defaults script, boot anim. Device already has the boot anim,
  bridge with standby, frontlight; NOT yet: gesture-nav overlay config and defaults script
  (both only matter on fresh installs). Flash without wipe:
  `adb reboot fastboot` → check `is-userspace: yes`, `current-slot: b` →
  `fastboot flash system_b <img>` → `fastboot reboot`.

## Next build — to test
- **Auto power-off** (like stock Moaan): InkControl → "Auto power-off": Never / 4 / 8 / 12 /
  24 h asleep. Alarm armed at screen-off on battery (or unplug while asleep), cancelled at
  screen-on / plug-in (`AutoOff.java`); on expiry InkControl writes `power.req` and the bridge
  shuts down only if `dumpsys power` isn't Awake and `dumpsys battery` shows nothing powered
  (`eink-apply.sh`). **Not in `system-vanilla-next.img` yet: re-run bake.sh before flashing**,
  then reinstall InkControl (section stays hidden until the new bridge is on the device).
  Check: SELinux lets phhsu_daemon run `dumpsys` + `svc power shutdown` (logcat avc if not);
  `mWakefulness=Awake` matches A16 output; screen-on before expiry cancels; plugged in never
  shuts down. A temporary 2-min option would make testing quicker.

- **Bridge watches InkControl AND InkPalm+** (`/data/data/{org.neoport.inkcontrol,com.inkpalmplus}/files`),
  one inotifyd loop each (verified live from a temp copy: com.inkpalmplus eink.req → mode 13).

## Decided: InkPalm+ absorbs InkControl (2026-10-23)
- Merged app = InkPalm+ codebase/package (`~/Github Repos/inkpalm+`, com.inkpalmplus, public via
  Obtainium). Moves in: InkControl's backends (binder / direct / bridge), QS tiles, frontlight,
  sleep screen, auto power-off, KompaktOS sync, repaint-on-mode-change. InkControl retired after.
- Gestures: right edge = recents panel (as now); **left edge = e-ink + light panel** (presets,
  "use for this app", full refresh, light sliders) — moves the light rows out of the recents panel.
  Mid-edge vertical swipe, so gesture-nav Back still works. Drop InkControl's light edge strips.
- Capacitive button = KEY_HOMEPAGE on fts_ts (inkpalm+ docs/firmware.md) → Home on KompaktOS
  (Moaan's PhoneWindowManager actions are gone). Merged app can take tap/hold via its a11y key
  filter. **Confirmed by user:** acts as Home on KompaktOS, via the InkPalm+ service.
- Own build: platform-signed copy can drop Shizuku + hiddenapibypass.

## Flashed 2026-10-23 13:13: `~/InkPalm-Images/kompaktos/baked/system-vanilla-20261023b.img` on system_b
- Baked 2026-10-23 from vanilla/system.img + vlib64-WORKING + fts_ts.idc + BOOTANIM, 3195027456
  bytes (= system_b), sha256 c9ae80f3f8a87f65…, fsck clean, scripts + rc + labels verified against the repo. (system-vanilla-next.img
  deleted after the flash; system-vanilla.img kept as rollback.)
- Adds over the device: auto power-off bridge, bridge for InkControl+InkPalm+, seeds
  fullmode_cnt=40, eink.full / sys.gray.gammalevel / poweroff image
  requests, gesture-nav overlay config, defaults v1+v2. All bridge requests tested live from
  copies (shutdown stubbed).
- Defaults v2 (stock behaviour KompaktOS lost; already applied by hand on the device): animations
  0, battery %, heads-up off, screen timeout 1 min, FUTO keyboard + EinkBro browser if installed.
  User chose NOT to re-enable Key Mapper. Stock sleep-image darkness
  (persist.sys.mogu.wallpaper_gamma=0.1) tried and rejected by the user ("too dark") — left unset.
- Not restorable as settings: stock UI gamma (debug.sf.gamma.gamma, Rockchip SurfaceFlinger
  only) → use sys.gray.gammalevel; logo-key long press = full refresh → merged app key filter;
  stock font (deleted with /data/mogu, never backed up).
- Edge Back gesture: KompaktOS builds with config_showNavigationBar=false (vendor/kompakt
  overlay), so no nav bar → A16 never attaches EdgeBackGestureHandler. phh navbar overlay /
  Lineage force_show_navbar tried + reverted (no nav bar appears). Decided: merged app does Back
  from an edge swipe now; own build restores the native gesture later.
- **Power-off screen:** HWC draws /data/misc/poweroff.png (poweroff_nopower.png if
  sys.power.status=1) on the display power-off transition while sys.power.shutdown=1 — stock
  ShutdownThread did that; KompaktOS doesn't. `inkpalm-poweroff.sh` (rc: on
  sys.shutdown.requested, shutdown only, only if a custom image exists) sets the props and
  wakes/sleeps the display. Verified without shutdown: English panda (composed from
  /vendor/media art, not in the repo) shown by the user's device. **Next-build test:** real
  shutdown from the power menu and from auto power-off shows it. English images are already
  installed in /data/misc on the device. Setting lives in InkPalm+ (merge session).
- After flash: booted; bridge watches both apps; fullmode_cnt=40, rt=0; defaults v1+v2 ran;
  diag 25 PASS. Known, pre-existing: Perfetto `traced` crash-loops at boot — stock
  /product/etc/build.prop sets traced.relay_producer_port=vsock://-1:2010 and the 4.19 kernel
  has no vsock (errno 97). Harmless (tracing only); fix later by clearing the prop early in
  our rc. Widevine L3 only (no liboemcrypto) — normal on a GSI.
- Still to test on the new image: auto power-off end to end (real shutdown, shows the panda),
  power-menu shutdown shows the panda, frontlight after long unplugged sleep, microG Self-Check.
- After the device work (incl. the InkPalm+ merge session's testing): user turns off Rooted
  debugging.

## InkControl (tools/inkcontrol/, org.neoport.inkcontrol)
- Backends: stock Moaan `eink` binder / direct (platform-signed build on test-keys GSIs) /
  bridge (KompaktOS, release-keys). Per-app modes (re-applied; stock SystemUI forces 7),
  KompaktOS-named preset tiles, refresh, KompaktOS refresh piggyback.
- QS tiles draw their names as icons (KompaktOS QS is icon-only); labels "InkPalm: …".
  KompaktOS SystemUI ignores `cmd statusbar add-tile`/`set-tiles` (removes work) — the user
  adds tiles via the pencil editor. KompaktOS's own e-ink tiles don't drive this panel.
- Frontlight (Boox-style): independent cold/warm levels + switches, scaled by system
  brightness (optional), panel from the "Frontlight" tile, optional edge swipe (user found it
  rough; keep off). Off at screen-off, restored at screen-on (driver drops levels on suspend).
- Public light API (unprotected): provider `content://org.neoport.inkcontrol.light/state`,
  broadcast `org.neoport.inkcontrol.action.SET_LIGHT` → used by **inkpalm+ side panel**
  (brightness + warmth; built in the Inkpalm+ session, its commit f21d80c).
- Sleep-screen picker (InkControl → Sleep screen).
- Reinstall needs: `adb install -r --no-incremental build/inkcontrol.apk`, `pm grant …
  WRITE_SECURE_SETTINGS`, `appops set … WRITE_SETTINGS allow`, and re-writing
  `enabled_accessibility_services` (Android drops the service on update).

## Backups / revert
- `~/InkPalm-Backup/` — sdcard + Android/data, APKs, app exports, screenshots, and
  `partitions-full/` (all stock partitions incl. super, sha-verified). Revert: flash stock
  `super.img` + `fastboot -w` (docs/FLASH-KOMPAKTOS.md, docs/REVERT.md).
- Images: `~/InkPalm-Images/` (~25 GB; kompaktos/, lineage-21*, a16/, stock-libs/).

## Open items
- E-ink preset → mode mapping (Fast=12, Soft=14, Dither=13, Text=8, Quality=7, Auto=22):
  user saw **no difference** on KompaktOS. Vendor HWC `ReassessmentEpdMode` (0x1a830,
  disassembled 2026-10-23) decides by `persist.sys.mogu.refresh_type`: **0 = sys.eink.mode as
  requested** (KompaktOS default), 1/2/4+ = re-picked by screen content (text/cartoon/image),
  3 = always 9 (PART_GLR16); system_type≠0 with rt≠0 = always 22. Stock ran rt=2 (content
  based), so stock presets were partly cosmetic too. Ghost clearing: `persist.vendor.fullmode_cnt`
  (full refresh every N partials; default 500, stock 40) → bridge seeds 40; on-demand full
  refresh = bump `sys.eink.one_full_mode_timeline` (≥0.5 s apart). EPD enum: 2 FULL_GC16,
  7 PART_GC16, 8 PART_GL16, 9 PART_GLR16, 12 A2, 13 A2_DITHER, 14 DU, 21 FORCE_FULL, 22 AUTO_DU.
  Real cause of "no difference": a new mode only applies to pixels drawn after it, and tiles
  didn't redraw anything (the old "flash" set mode 2 for 700 ms with no new frames, so Full
  refresh was a no-op too). Fixed: tiles/refresh show a 150 ms white accessibility overlay
  after the mode lands (`AppWatcherService.repaint`). **Verified by user 2026-10-23** (A2
  gradient = pure black/white; Fast vs Quality visibly different). Device: rt=0 and
  fullmode_cnt=40 set by hand (bridge seeds fullmode_cnt on next flash).
- Capacitive button: done — KEY_HOMEPAGE, acts as Home via InkPalm+ (see the merge section).
- Unplugged long-sleep light restore: user to confirm after a real suspend.
- Native QS warmth slider / KompaktService driving the panel need our own KompaktOS build —
  **user has no Linux build host** (none planned), so stay with InkControl + bridge.
- tools/diag/run_diag.sh rewritten for KompaktOS (unrooted ok); not yet run live there.
- Optional bridge idea from e-ink subagent: copy KompaktService prefs for per-app sync.
