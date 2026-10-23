# Sleep screen (standby image) on the InkPalm Plus

Static research only (no device access). Sources: vendor dump `~/InkPalm-Images/dsu-boot-20261023-002648/vendor`
(`/vendor/lib64/hw/hwcomposer.rk30board.so`, sha256 69fd2fc5...0f12b, disassembled with llvm-objdump; no Ghidra available, so
control flow below was read from the AArch64 disassembly), stock `framework.jar` / `MoanLauncher.apk` / `services.jar`
(dexdump) in `~/InkPalm-Backup/system-ref/`, `vendor_property_contexts`, `vendor_sepolicy.cil`.

## 1. Mechanism: the vendor HWC draws it, not the kernel and not SystemUI

When SurfaceFlinger calls HWC `setPowerMode(display, mode)` with **OFF (0)**, the Moaan HWC (`hwc_set_power_mode`, the
big function at 0x11150 that the symbol table mislabels as `hwc_post_epd_logo+...`) picks a PNG, decodes it itself
(`drawLogoPic`: libskia decode, rotate by `persist.sys.mogu.rotation`, gamma by `persist.sys.mogu.wallpaper_gamma`, convert
to gray16 with `logo_gray256_to_gray16`) and posts it to the panel through `/dev/ebc` (`hwc_post_epd_logo(const char*)`, EBC ioctls).
The panel is bistable, so the image simply stays after the display is powered down. Modes 2/3 (ON/DOZE_SUSPEND) take the
"wake" branch; only mode 0 draws an image (disassembly 0x11188: `w19-2 < 2`, then `cbnz w19`).

Image selection when mode == OFF (strings and `access()` calls in the disassembly, 0x11238-0x11a40):

| Condition | Path tried first | Fallback |
|---|---|---|
| `sys.power.shutdown == 1` (shutdown) | `/data/misc/poweroff.png` (or `poweroff_nopower.png` if `sys.power.status==1`) | `/vendor/media/poweroff.png`, `/vendor/media/poweroff_nopower.png` |
| `persist.sys.moaan.yifengxin == 1` | `/vendor/media/yifengxin.png` | none |
| `sys.power.connected == 1` (charging) | file named by `persist.sys.mogu.wallpaper` (if it exists) | `/data/misc/standby_charge.png`, then `/vendor/media/standby_charge.png` |
| `sys.power.status == 1` (low power) | `persist.sys.mogu.wallpaper` file | `/data/misc/standby_lowpower.png`, then `/vendor/media/standby_lowpower.png` |
| otherwise (normal sleep) | **`persist.sys.mogu.wallpaper`** (default string `"test"`, so unset = skipped) | **`/data/misc/standby.png`**, then **`/vendor/media/standby.png`** |

Log lines the HWC prints for each branch: `hwc_set_power_mode ... user_def_img = <prop>`, `linfeifei wallpaper,use it.`,
`/data/misc/standby.png not found, use /vendor/media/standby.png` (only emitted when `log_level()` allows; see test plan).
`ro.need.white.with.standby` is also read in this function (white flash before standby; exact semantics UNVERIFIED).

Evidence that it is not the other candidates:
- Kernel `logo` partition: only the boot/uboot logo. No HWC string refers to it; the strings in the HWC name only PNG paths above and `/dev/ebc`. The kernel image itself was not in the dump, so a kernel-side standby picture cannot be fully ruled out, but nothing in userspace feeds it one.
- SystemUI / framework: they only choose the image, they do not draw it. `framework.jar` has `android.os.MoanWallPaper`
  (public API of the Moaan ROM, hidden): `setCustomWallPaper(Context,String)` copies the source file to `data/mogu/<SDBM-hash-of-path>.png`
  (relative path, no leading `/`; `setCustomWallPaperNew` first rescales to 1264x1680 unless width 700..1500 and height 1000..1800), deletes the previous
  custom file (unless the path contains "almanac"), then calls `ActivityManager.setSystemProp("persist.sys.mogu.wallpaper", path)`.
  `setCustomWallPaperShutDown` does the same into `data/mogu/<hash>_shutwodn.png` + `persist.sys.mogu.shutdown_wallpaper`
  (note: the HWC strings never mention `shutdown_wallpaper`, so that prop appears to be consumed only by the framework; UNVERIFIED).
  `MoanWallPaper.goToSleep()` just calls `PowerManager.goToSleep`.
- `MoanLauncher.apk` runs a `WallpaperService` (`mnt/sdcard/Wallpaper` folder, `local_wallpaper`, alarm-based `setWallPaperAlarm`, action `com.moan.update_refresh_wallpaper`) that feeds `MoanWallPaper`. The user's backup `sdcard/Wallpaper/` is that folder.
- Stock device value: `persist.sys.mogu.wallpaper=data/mogu/136572479.png`, `wallpaper_gamma=0.1`, `rotation=0`. Vendor `standby.png`
  (`standby_charge.png`, `standby_lowpower.png` are byte-identical copies, 178599 bytes) is 720x1440 RGB PNG.
- Props are labelled `vendor_ebook_prop` (`vendor_property_contexts` lines 94-101); sepolicy lets `shell`, `system_app`,
  `platform_app`, `system_server`, `vendor_init` and the HWC itself *set* it, and everyone incl. untrusted apps read it.
- File access: the HWC domain `hal_graphics_composer_default` may read only `system_data_file` under /data (cil line 1490), plus vendor files.
  So the image must be a `system_data_file`-labelled file; `/data/local/tmp` (`shell_data_file`) and `/sdcard` are NOT readable by it.

## 2. Setting a custom image

Image format: PNG, 720x1440 (panel portrait), RGB/gray 8-bit. Pre-dither/convert to 16 grays yourself; gamma default 0.1 on stock.
Prefer a plain black-on-white or high-contrast image; rotation prop 0 means no rotation.

### (a) Stock firmware (non-root)
- Supported route: the Moaan launcher/settings wallpaper UI (which calls `MoanWallPaper.setCustomWallPaper`). Put the PNG in
  `/sdcard/Wallpaper/` (adb push, or MTP) and pick it in the launcher's wallpaper chooser. Exact menu UNVERIFIED (not in the APKs we have besides `WallpaperService`).
- adb alone cannot import a new file: `shell` can **set** the props, but cannot write to `/data/mogu` or `/data/misc`.
  What adb *can* do is switch between files that already exist in `/data/mogu`: `adb shell setprop persist.sys.mogu.wallpaper data/mogu/<existing>.png`
  (shell has `property_service set` on `vendor_ebook_prop`, cil line 2038). `/data/mogu` listing is probably denied to shell; use the files the launcher imported.
- Third-party apps (InkControl) cannot call `MoanWallPaper` (hidden API, system-only write of the prop via `setSystemProp`); a targetSdk-30 app could try reflection but `setSystemProp`
  needs a signature permission. Not recommended.

### (b) GSI (adb root available)
No Moaan framework is present, so the prop is never set and `/data/mogu` doesn't exist; the HWC falls to `/vendor/media/standby.png`
(the stock Moaan art the user sees now). Two equivalent ways, no sepolicy change needed as long as the file ends up `system_data_file`:

1. Standard-path (simplest, no prop):
   `adb root; adb push sleep.png /data/misc/standby.png; adb shell chmod 644 /data/misc/standby.png; adb shell chown system:system /data/misc/standby.png; adb shell restorecon /data/misc/standby.png; adb shell ls -Z /data/misc/standby.png`
   (also push `standby_charge.png` / `standby_lowpower.png` copies if the charging/low-power cases should match; `sys.power.status/connected` are set by Moaan's services.jar so they stay unset on a GSI, so only `standby.png` matters unless we add a setter).
2. Prop-path (what stock uses): `adb shell mkdir -p /data/mogu; adb push sleep.png /data/mogu/sleep.png; adb shell chmod 644 /data/mogu/sleep.png; adb shell restorecon -R /data/mogu; adb shell setprop persist.sys.mogu.wallpaper /data/mogu/sleep.png`
   (absolute path is fine; stock stores a relative path because the HWC's cwd is `/`). `persist.sys.mogu.*` resolves to `vendor_ebook_prop` through the vendor property_contexts, which a GSI keeps.
   `/data/mogu` must end up `system_data_file` (check `ls -dZ /data/mogu`; if it is `unlabeled` or something else, the HWC gets an avc denial).

For the final image: ship the default PNG in the GSI (`/system/etc/...` is NOT readable by the HWC domain, so instead let the einkservice copy it to `/data/misc/standby.png` on first boot, running as `system` with a sepolicy allow for `system_data_file` write), and expose a "Set sleep image" action in InkControl/einkservice that decodes, rescales to 720x1440, writes the file and (optionally) sets the prop. If the einkservice cannot set `persist.sys.mogu.*`, use the `/data/misc/standby.png` route (plain file write, no property permission).

Alternative that needs no runtime step: overlay `/vendor/media/standby.png` by bind/overlay mount (DSU test already overlays `/vendor/lib64`), but a flashed vendor change violates the "vendor untouched" goal; avoid.

## 3. Adb test plan (GSI, root; do not run on the device while another agent is using it)
1. Baseline: `adb shell getprop | grep -i mogu`; `adb shell ls -lZ /data/misc /data/mogu /vendor/media/standby.png`.
2. Enable HWC logs (gating is `log_level()` reading `sys.hwc.log`; value semantics UNVERIFIED, try): `adb shell setprop sys.hwc.log 7`.
3. Install image via route 1 or 2 above. Verify `ls -Z` shows `system_data_file` (or whatever label the HWC may read).
4. `adb logcat -c; adb shell input keyevent KEYCODE_SLEEP` (or briefly press power). Wait 3-5 s. Check the panel shows the new image (it persists with the display off).
5. `adb logcat -d | grep -iE "hwc_set_power_mode|user_def_img|standby|drawLogoPic|avc: denied.*hal_graphics_composer"`. Expected lines:
   `user_def_img = /data/mogu/sleep.png` (route 2) and `... exist,use it` or `/data/misc/standby.png ...`; `drawLogoPic decode_image_file error path:` means bad PNG or unreadable file.
   Any `avc: denied ... scontext=...hal_graphics_composer_default ... tcontext=` names the label that needs fixing.
6. `adb shell dumpsys power | grep mWakefulness` should read `Asleep`. Wake: `adb shell input keyevent KEYCODE_WAKEUP`.
7. Negative tests: remove the file and sleep again (must fall back to `/vendor/media/standby.png`); try a 1080x2160 PNG (does the HWC scale? unknown) and `persist.sys.mogu.rotation=1`, `persist.sys.mogu.wallpaper_gamma=0.5`.
8. If nothing is drawn although files exist: confirm SurfaceFlinger actually issues mode OFF (GSI may use doze states: `adb shell dumpsys display | grep -i state`; only mode 0 draws), and that `hwcomposer` and `/dev/ebc` (`chmod 0666` via init) are alive (`tools/diag/run_diag.sh` display_stack check).
9. Stock check (read-only): `adb shell getprop persist.sys.mogu.wallpaper` should print `data/mogu/<digits>.png`; after choosing a wallpaper in the Moaan launcher the value changes and the screen-off image changes.

## Verified on device (2026-10-23, LineageOS 21 DSU boot)
A 720x1440 PNG copied to `/data/misc/standby.png` (+ `standby_charge.png`, `standby_lowpower.png`),
`chown system:system`, `chmod 644`, `restorecon` (→ `system_data_file`) is shown by the vendor
HWC as the sleep screen on the next power-button sleep. (Tested while SELinux was permissive
on that boot; re-check on an enforcing boot.)
