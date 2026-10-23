# GSI + KompaktOS-features scoping for the Moaan InkPalm Plus (rk3566)

Research only; nothing was run on a device. "UNVERIFIED" marks claims I could not source. Date of research: 2026-10-22.

## 0. Headline finding

KompaktOS is **Android 16 (LineageOS 23.2) running on a Linux 4.19.191 kernel with an Android 12 vendor**
(https://github.com/gezimos/KompaktDevice/blob/main/docs/Vendor.md, docs/Kernel.md). So an old kernel and an old vendor
are not blockers for a modern GSI by themselves. The Kompakt ROM needed only a handful of GSI-side fixes for 4.19
(see section 2), but it also ships its own kernel, vendor image and sepolicy edits, which we cannot replicate on the InkPalm
(no kernel source known; see section 5).

## 1. Ready-made arm64 GSIs

| GSI | Android | Where | Variants / compressed size | Notes |
|---|---|---|---|---|
| AndyYan LineageOS 20 TD | 13 | https://sourceforge.net/projects/andyyan-gsi/files/lineage-20-td/ (latest 2025-10-21) | arm64_bvN 996 MB, bvN-vndklite 989 MB, bvS (su) 998 MB, bgN-signed 1.2 GB (all .img.gz) | Last A13 build 2025-10; "light" A13 folder frozen 2024-04 |
| AndyYan LineageOS 21 TD (QPR3 base) | 14 | https://sourceforge.net/projects/andyyan-gsi/files/lineage-21-td/ (2025-06-22) | | |
| AndyYan LineageOS 21 "pre-qpr2" TD | 14 | https://sourceforge.net/projects/andyyan-gsi/files/lineage-21-pre-qpr2-td/ (2026-06-14 build) | arm64_bvN 1.2 GB, bvN-vndklite 1.1 GB, bgN-signed 1.4 GB, bgN-vndklite-signed 1.4 GB | Newest A14 build, still updated in 2026. "pre-qpr2" is the better choice for older vendors (UNVERIFIED rationale; the folder name implies a base before A14 QPR2) |
| AndyYan LineageOS 22.2 "light" | 15 | https://sourceforge.net/projects/andyyan-gsi/files/lineage-22-light/ (2025-06-21) | gsi_arm64_vN 1.1 GB, gN-signed 1.4 GB | Light variant, not TD-based |
| MisterZtr LineageOS 22.2 | 15 | https://github.com/MisterZtr/LineageOS_gsi/releases (2026.01.05) | VANILLA-EXT4 0.8 GB (2.4 GB raw?), GAPPS-EXT4 1.0 GB (3.1 GB), EROFS variants smaller | |
| MisterZtr LineageOS 23.2 | 16 | same releases page (2026.05.24, "Android 11 vendor support") | VANILLA-EXT4 0.9 GB (2.5 GB), GAPPS-EXT4 1.1 GB (3.2 GB), VANILLA-EROFS 1.0 GB (1.7 GB) | Same base KompaktOS uses. Page: "EROFS requires kernel 5.4+" so pick **EXT4** on 4.19. The parenthetical sizes are not explained on the page; I read them as uncompressed size (UNVERIFIED) |
| TrebleDroid AOSP | 13, 14, 15, 16 | https://github.com/TrebleDroid/treble_experimentations/releases (A15 ci-20250415 latest "stable"; A16 ci-20250617 pre-release) | asset sizes not visible in my fetch | The phh wiki lists only TrebleDroid builders for AOSP 13+; no newer phhusson-personal AOSP |
| phh GSI list (index of all of the above) | | https://github.com/phhusson/treble_experimentations/wiki/Generic-System-Image-(GSI)-list | | |

Naming: `b` = system-as-root/bootless A/B, `v` = vanilla, `g` = GApps, `N` = no su, `S` = su; `-vndklite` strips VNDK 28/29 to save space (AndyYan SourceForge listing; MisterZtr README for build targets: https://github.com/MisterZtr/LineageOS_gsi).
AndyYan's "TD" builds use the TrebleDroid device tree (phh-style `device/phh/treble`), which is what KompaktOS also builds from.
Our vendor is API 30, so the 28/29 VNDK trimming is irrelevant; plain `bvN` is fine and `vndklite` saves ~10 MB only for A13.

**Compatibility on rk356x:** I found **no** published report of any Treble GSI booting on RK3566/RK3568, nor any InkPalm Plus root/ROM thread
(searched: XDA/GitHub/general web; the InkPalm Plus pages only list specs: https://www.cnx-software.com/2022/05/25/150-inkpalm-plus-ereader-features-rk3566-soc-5-84-inch-display/).
Treat "works on rk3566" as **untested**. Positive indirect evidence: the device is Treble-enabled with a VNDK-30 vendor, the stock 4.19 kernel
is within what GSIs tolerate (section 2), and KompaktOS proves a 4.19 / old-vendor / e-ink phone can run a GSI.
Likely failure points: SELinux denials on Rockchip HALs after the forced policy recompile (the Kompakt needed fixes for orphaned vendor types, see Vendor.md section 2 and `device_phh_treble/0002`), the Rockchip hwcomposer/gralloc expecting stock framework props, and the missing EinkService (section 3).

**Fit in super (5 GiB, A/B, no Virtual A/B):**
- Raw ext4 system sizes: A16 vanilla ~2.5 GB, GApps ~3.2 GB (MisterZtr). A13/A14 are roughly similar or slightly smaller (UNVERIFIED; AndyYan lists compressed sizes only, ~1.0-1.4 GB gz).
- Stock vendor 0.5-1 GiB + odm (+ product if kept).
- **Important risk:** on non-VAB A/B, super holds *both* slots. The OEM usually defines two groups (one per slot) each capped at roughly `(super - metadata)/2` ~ 2.5 GiB (AOSP dynamic partition rule; exact group_size must be read from the device's LP metadata, UNVERIFIED for this device). Then system 2.5 GB + vendor 0.6 GB + odm exceeds a ~2.5 GiB slot group even if the super has free space, and `delete-logical-partition` does not raise the group cap.
  Check with `lpdump` on the super dump (host-side; the user supplies the dump) before choosing. If the cap is binding: (a) use the smallest image (A13/A14 vanilla bvN, vndklite), delete `product_b`; (b) delete the inactive slot's `*_a` partitions and, if needed, **rebuild the super image on the host with `lpmake` with a single big group** and flash it by Rockchip tools; (c) as a last resort a custom-repacked system.img trimmed of apps.
- GApps images almost certainly need option (b).

## 2. Kernel 4.19 requirements by Android version

| Android | Constraint on 4.19 | Source |
|---|---|---|
| 13 (T) | bpfloader: "Android S & T require kernel 4.9." Fine on 4.19. | https://android.googlesource.com/platform/packages/modules/Connectivity/+/refs/heads/main/bpf/loader/NetBpfLoad.cpp |
| 14 (U) | "Android U requires kernel 4.14." Fine. | same |
| 15 (V) | "Android V requires kernel 4.19." **Exactly the minimum.** Same file also logs (does not abort on) "Android V+ only supports LTS kernels", with 4.19.236 as the floor; a 4.19.193 kernel would log an "unsupported kernel version" error but is not blocked. | same |
| 16 (B), 25Q2 bpfloader | Source main branch says "25Q2 bumps the kernel requirement up to 5.4. Android 25Q2 requires kernel 5.4." But **KompaktOS (LineageOS 23.2/A16 QPR2) boots on 4.19.191** and MisterZtr's 23.2 release says it supports A11 vendors, so the 5.4 gate either is not in the shipped Connectivity branch or is only hit with the mainline module build (UNVERIFIED which). Do not assume A16 works; the Kompakt evidence is the only proof. | same; https://github.com/gezimos/KompaktDevice/blob/main/docs/Kernel.md |
| EROFS GSI | Needs kernel 5.4+ and fstab entries; pick ext4 images. | https://github.com/MisterZtr/LineageOS_gsi/releases |
| GKI | Android 13-16 officially list kernels android12-5.10 and newer only; 4.19 is outside the official matrix, so it relies on legacy "launch-with" vendors. | https://source.android.com/docs/core/architecture/kernel/android-common |

Known 4.19 fixes needed by A16 on the Kompakt (the GSI-side bits, generic to any 4.19 device), from https://github.com/gezimos/KompaktOS/blob/main/patches/README.md:
1. **bionic `posix_spawn` CLOEXEC**: `close_range(CLOSE_RANGE_CLOEXEC)` needs 5.11; on 4.19 vfork child exits 127 silently, breaking netd's dnsmasq (hotspot DNS) and clatd. Patch walks `/proc/self/fd`. A14/A15 bionic: not checked whether the same call exists (UNVERIFIED), so expect hotspot/clat quirks only. Wi-Fi client use is unaffected.
2. `packages_modules_Connectivity/0001`: tethering DNS proxy fallback (hotspot only).
3. `device_phh_treble/0002`: sepolicy `roletype` binding so secilc recompile does not abort/bootloop for orphaned vendor types. A generic *class* of problem: any vendor whose `*_31_0`/`*_30_0` mapping has unbound types can bootloop when a GSI forces a policy recompile. Expect to hit it on rk356x.
4. Kernel config `CONFIG_STATIC_USERMODEHELPER_PATH` pointing into a path absent on a GSI (usermode helpers silently fail). Minor.

The EOL note: Kompakt kernel docs say 4.19 is past upstream EOL (Dec 2024) and the vendor BSP cannot be ported forward (Kernel.md).
Vendor interface window: FCM table starts at level 6 = Android 12 on the cited page; "202404 and later support the current and six previous FCM versions" (https://source.android.com/docs/core/architecture/vintf/fcm). Android 11 = FCM 5, so for A13/A14 an A11 vendor is certainly in range; for A15/A16 it is borderline (not stated on page); MisterZtr's explicit "Android 11 vendor support" in 23.2 is the best A16 evidence.

## 3. KompaktService: how it drives e-ink, and the Rockchip delta

Source: https://github.com/gezimos/KompaktOS/tree/main/vendor/kompakt/KompaktService (≈40 Kotlin files, `jni/buttons.c`, `jni/tty.c`, `kompakt_service.rc`). It is a **uid system app** (`sharedUserId android.uid.system`) installed in the system image. Hardware access is mostly plain sysfs file writes (`Sysfs.putBlocking`, `File(path).writeText`), with no ioctls for e-ink. JNI is only for buttons (`buttons.c`) and USB serial tty (`tty.c`).

E-ink control path (`Hardware.kt` object `Eink`, `EinkAppWatcher.kt`, `Flash.kt`, `AppInvert.kt`, `RefreshReceiver.kt`):
- Writes `/sys/einkinfo/{waveform_mode,pixelbits,gamma,brightness,contrast,dither_type,dither_param,timings_mode,eink_temperature,clear}`. Six presets (fast A2, soft, fast+dither, text GL16, quality, auto). "Auto" uses a custom `KAUTO` waveform name implemented by their own kernel module and is detected by read-back.
- `clear` node = full-panel flush; also `Flash.kt` draws a black/white overlay window for 480 ms (portable, framework-only).
- Per-app modes: `EinkAppWatcher` is an `AccessibilityService` on `TYPE_WINDOW_STATE_CHANGED` which maps foreground package -> mode (prefs) and calls `Eink.setMode`. Portable as is.
- Per-app inversion: `AppInvert` toggles `Settings.Secure.ACCESSIBILITY_DISPLAY_INVERSION_ENABLED` per foreground app. Portable (needs WRITE_SECURE_SETTINGS).
- Long-press home -> broadcast to `RefreshReceiver` -> flush (patched into frameworks_base 0016/0035; the broadcast target is portable).
- `UnlockRefresh`, `LockFlash` (`/sys/module/meink_hal/parameters/deghost_every`), `SleepImage` (`/sys/einkinfo/sleep_image`), temperature offset: all depend on Kompakt's own kernel modules; skip or re-implement.
- QS tiles (`Tiles.kt`, `EinkTileService`s) expose modes; portable.
- Access control: Kompakt had to change vendor sepolicy and `init.project.rc` so `system_app` can write each `/sys/einkinfo` node, plus `kompakt_service.rc` for chmod/chown.

Other features in the service (mostly hardware-specific, skip for InkPalm): `Battery` (`/sys/kernel/battery_monitor`), `OfflineSwitch`, `ESim` mux, `Torch` (two flash LEDs), `FrontLight` (brightness steps via DisplayManager; the stepping logic is portable, the hardware is not unless InkPalm has a front light, UNVERIFIED), `FingerScroll` (fingerprint nav from logcat), `Buttons` (JNI), `Ims`/`SimModeActivity`, LED migration, `link/*` (USB serial desktop link), `GsfId`, `TetherOffload`.

**Port to Rockchip** (given `hwcomposer.rk30board` reads `sys.eink.*`, kernel `/dev/ebc` + `/dev/waveform`, stock `EinkService` binder "eink" / `IEinkManager`):
1. Replace `Eink.setMode` + `write()` with a new backend. Option A (simplest, no framework patch): `SystemProperties.set("sys.eink.mode", N)` etc. from the system app. Requires the property to be settable from the app's domain: the property label lives in the stock vendor's `property_contexts`; a GSI forces a plat/vendor policy combination where `system_app` has no `set_prop` for it. Fixes: (i) patch GSI `system/sepolicy` (needs building the GSI; a vanilla image can't do it), (ii) ship an `init` rc fragment that watches an allowed trigger property and does `setprop sys.eink.mode ...` (init can set anything; rc fragments in `/system/etc/init` need the image rebuilt, but phh/TrebleDroid has a hook for `persist.sys.phh.*` triggered scripts, UNVERIFIED), or (iii) `adb root`/`su` style `setprop` for testing.
   Option B: re-implement `IEinkManager` as a small system service/Binder (recover the AIDL from the stock services.jar via the decompiled `android.os.IEinkManager`) so apps and our service talk to the same API as before; only needed if the stock Rockchip HWC/ebc library requires the binder to be registered (UNVERIFIED; check logcat for the hwc complaining about missing "eink" service).
2. Mode mapping table (to be derived from stock `EinkService` / Rockchip e-ink settings): A2/DU/GL16 style presets -> `sys.eink.mode` integer values; contrast/dither/gamma may not exist. Expect fewer controls than Kompakt (no per-nibble waveform tweaks).
3. `Flash` overlay stays; replace `clear` with a stock "full refresh" prop/ioctl via the same backend.
4. Drop AOD, SleepImage, Battery, eSIM, Torch, LED, offline switch, tty link.
5. Effort estimate for a new `InkPalmService`: 2-4 days if props are enough and sepolicy is solved; 1-2 weeks if a full IEinkManager shim plus ebc-specific refresh is needed. Unknowns dominate (need on-device investigation of stock EinkService, outside this task).

## 4. Patch classification

Totals in `patches/kompakt/` (https://github.com/gezimos/KompaktOS/tree/main/patches/kompakt): frameworks_base 119 files, device_phh_treble 15, packages_apps_* ~85 (Twelve 13, Etar 9, WallpaperPicker2 8, Contacts 8, Settings 7, DeskClock 7, Launcher3 6, DocumentsUI 6, Dialer 6, Aperture 6, Messaging 4, Updater 4, LineageParts 4, ThemePicker 3, LatinIME 3, Jelly 2, AudioFX 2, CarrierConfig 2), frameworks_opt_telephony 6 + treble_app 6 + vendor_apn 3 + CarrierConfig (telephony, all skip), frameworks_av 3, frameworks_native 2, vendor_lineage 5, lineage_sdk 3, hardware_lineage_interfaces 3, bionic 2, others small.

frameworks_base 118 (my classification from patch **titles + README only**; I did not read the diffs, so numbers are +/-10):

| Class | Approx. count | Examples (patch numbers) |
|---|---|---|
| Generic e-ink UI, portable in concept | ~40 | no scrim 0001, no marquee 0002-3, no dim 0013, theme two inks 0037-38, status bar monochrome/battery 0012/0025/0026, no ripples 0051, animation scale hooks 0049/0053/0058, dialog borders 0033/0050, monochrome emoji 0074, volume dialog 0027/0061/0064/0067-68/0106, system font 0087, monochrome app icons 0066/0095, SettingsLib one-row toolbar + paged settings 0007/0102/0104, QS tile editor/e-ink group 0108-0109 |
| Android-16-only SystemUI (scene container "flexiglass", dual shade, Compose bouncer/lockscreen, SPA settings) | ~45 | shade/QS 0006/0009/0011/0017/0018, lockscreen clocks and notifications 0054/0069-0073/0075-0086/0089-0090/0096/0110/0112-0118, bouncer/PIN/pattern 0024/0044/0077/0078/0116-0117, SPA pages 0047/0055/0099, `build_release/0001` enables `scene_container` flag which "the SystemUI changes depend on" |
| Kompakt hardware-specific (skip) | ~25 | LED 0019/0022, key vibration 0042/0057, warm torch 0100/0101, SIM label/PIN 0044/0045, panel-off-until-first-frame 0020, AOD (needs `eink_aod_func`) 0004/0005/0028-0031/0036/0048/0056/0062/0063, unlock hook to Kompakt app 0043, camera/mic privacy indicator tweaks 0107 (generic) |
| Misc / small | ~8 | |

Other repos: telephony/IMS/APN/MTK modem/eSIM (OpenEUICC)/FM radio/charger (`kpoc_charger`)/fingerprint/`rw-system` scans: skip (~30 patches plus all of `vendor/kompakt/{mtkradioex,KompaktFMRadio,aee,charger}`). App patches (Twelve paged scrolling, Settings paged lists, Dialer, Contacts, DocumentsUI, Etar, DeskClock...) are portable as ideas but rebase per app version; they use the shared helper class `com.kompakt.eink.PagedScroll`/`PageGestureListener`.

Effort, rebasing onto LineageOS 20 (A13) or 21 (A14) trees (`device/phh/treble` TD tree):
- Not a clean cherry-pick. A16 SystemUI (scene container, Compose lockscreen/bouncer, flexiglass, dual shade, SPA settings) has no equivalent in A13/A14; those ~45 patches need to be **rewritten against the older Keyguard/NotificationPanel views**, not rebased.
- A14 (LOS 21): generic UI ~40 patches adapt with moderate conflicts (1-3 weeks), SystemUI rewrite for e-ink shade/lockscreen/bouncer ~3-6 weeks, plus build infra (250 GB tree, hours-long syncs). Total roughly **6-10 weeks** of focused work for a Kompakt-equivalent UI; **~2 weeks** for a minimal "theme + animations off + per-app modes + paged settings" subset.
- A13 (LOS 20): similar, a bit simpler SystemUI (pre-Compose), but OS is old/unsupported; 5-8 weeks full, 1.5 weeks minimal. AndyYan's A13 GSI is also in maintenance (2025-10-21).
- A16 (LOS 23.2) directly: patches apply nearly as-is (GSI base is identical to Kompakt's, MisterZtr manifest), so the **minimum-work** route is staying on Android 16 and just replacing hardware patches/service. Cost shifts to making A16 run on a 4.19 + A11 vendor (bpf 25Q2 5.4 gate, policy). Estimate 1-2 weeks for the port of the generic set + 2-4 days for service backend, **if** the vanilla GSI boots at all.
- Cheaper alternative for a subset: do not patch the framework; ship an RRO overlay + a system app (the Kompakt `overlay-static` approach, 534 files, https://github.com/gezimos/KompaktOS/tree/main/vendor/kompakt) and let a stock GSI do the rest.

## 5. Recommended path and step order

Recommendation: **(1) validate with an unmodified GSI first, (2) pick the Android version from what actually boots, (3) only then decide between "stock GSI + app" and "own GSI build".** Prefer **Android 14 AndyYan `lineage-21-pre-qpr2-td` arm64_bvN** as first try (vendor API 30 comfortably inside A14's window, bpf needs only 4.14, fits most easily), then try **MisterZtr LineageOS 23.2 VANILLA-EXT4** to leverage the Kompakt patch set, since Kompakt proves A16 boots on 4.19 and the Kompakt repo is rebased on it. Avoid EROFS and GApps initially.

Honest risk: the GSI may boot but show a blank e-ink panel because the Rockchip HWC/ebc path expects framework pieces we can't see (EinkService, `sys.eink.*` initial writes). Plan to reproduce them.

Steps (all for the owner to run; I touched no device):
1. Back up everything first: dump `super`, `boot_b`, `vendor_boot`/`dtbo`, `vbmeta*`, `misc`, `baseparameter`, `uboot/trust/resource` via the stock tool (Rockusb `rkdeveloptool`/`upgrade_tool`, or `adb pull /dev/block/by-name/...` when rooted). Keep the full stock firmware package ready for recovery; Rockchip maskrom/loader mode is the unbrick path (general Rockchip knowledge, UNVERIFIED for this device).
2. Inspect `lpdump` of the super dump (host) to read group names/sizes, current partition list/sizes. Decide whether the slot group cap fits system+vendor (section 1).
3. Fetch a vanilla GSI: `lineage-21.0-20260614-UNOFFICIAL-arm64_bvN.img.gz` (1.2 GB gz); `gunzip`. Verify it is a sparse/ext4 image.
4. `adb reboot bootloader`; `fastboot flashing unlock` is already done. Then:
   - `fastboot --disable-verity --disable-verification flash vbmeta vbmeta.img` (use a blank/stock vbmeta from the GSI project or the stock one; the XDA phh guides use this flag set: https://forum.xda-developers.com/oneplus-6/how-to/guide-how-to-flash-treble-roms-oneplus-6-t3797858/post76678385). Note: the user's `--disable-verity --disable-verification` flags go on `flash vbmeta`, with the vbmeta file; do it for `vbmeta_system`/`vbmeta_vendor` too if the device has them.
   - `fastboot reboot fastboot` (userspace fastbootd; from system `adb reboot fastboot`: https://source.android.com/docs/core/architecture/bootloader/fastbootd).
   - Optional if space is short: `fastboot delete-logical-partition product_b` (GSI includes its own product). Also consider deleting the inactive slot's logical partitions to free super space (breaks slot-a fallback).
   - `fastboot flash system_b system.img` (active slot is _b). In fastbootd you can also `fastboot resize-logical-partition system_b <bytes>` if needed.
   - `fastboot -w` (or `fastboot erase userdata` / `fastboot --wipe`) since /data encryption/format will differ; ensure the metadata partition is wiped too.
   - `fastboot reboot`.
5. If fastbootd is not available on this Rockchip bootloader: see gotchas; fallback is to repack super.img on the host (`lpmake`/`lpunpack` from AOSP) with the GSI as `system_b`, and flash the super over Rockusb.
6. Collect logs from first boot (the user can pull `last_kmsg`/pstore, `adb logcat -b all` once adb works): look at SELinux denials, hwc errors about e-ink, `init` policy compile errors.
7. Once a vanilla GSI boots and shows pixels: install the first-pass `InkPalmService` app (section 3) with props-based backend; test per-app mode + invert + flash.
8. Only then consider a custom GSI build: take MisterZtr's `treble_manifest`, apply the generic subset of KompaktOS patches, add the sepolicy/property/init fragment for `sys.eink.*`, and ship the InkPalm service in `/system` (privileged). Needs ~250 GB disk (Kompakt README: https://github.com/gezimos/KompaktOS).

Rockchip-specific gotchas (all UNVERIFIED for this unit unless noted):
- **fastbootd on Rockchip Android 11**: Rockchip's bootloader may only implement the older Rockusb/"fastboot" and rely on recovery for userspace fastbootd; the BCB `boot-fastboot` command in `misc` must be handled (AOSP spec: https://source.android.com/docs/core/architecture/bootloader/fastbootd). The user's earlier memory note says the stock tooling exists in this repo; check the ported tooling for whether `adb reboot fastboot` already works.
- `adb reboot fastboot` from the running system enters fastbootd if recovery/ramdisk has fastbootd (dynamic partitions are mandatory when super is present, so Rockchip must ship it, but I have no source for Rockchip-specific behavior).
- **`misc`** holds BCB/OTA state: a bad value can send the device to recovery loops; `fastboot erase misc` or rewriting the BCB is the usual fix.
- **`baseparameter`** is a Rockchip-specific partition storing display configuration (resolution/rotation/"scale") read by bootloader/HWC; I found no web source on it (search returned nothing relevant). The e-ink panel timing/rotation may live there or in `resource`/DTB. Do **not** erase it; back it up. A wiped `baseparameter` can give blank/rotated output.
- `uboot`/`trust`/`resource.img` (contains kernel DTB logo/DTB on Rockchip): untouched by a system-only flash. Keep `vbmeta` disabled or the AVB chain will refuse the GSI.
- A/B without VAB: `fastboot flash` to the inactive slot is not atomic; flash to the slot you boot (_b).
- Wi-Fi/BT firmware are in the vendor (kept), so only system-image HAL framework mismatches should matter.
- rk3566 has no AOD concept; ignore Kompakt's AOD patches (also the PowerVR GPU lockup patch is Mediatek-specific).

## 6. Sources
- KompaktOS: https://github.com/gezimos/KompaktOS (README, patches/README.md, vendor/kompakt/KompaktService/*)
- KompaktDevice: https://github.com/gezimos/KompaktDevice (docs/Vendor.md, docs/Kernel.md, docs/E-inkdriver.md)
- phh GSI list: https://github.com/phhusson/treble_experimentations/wiki/Generic-System-Image-(GSI)-list
- AndyYan SourceForge: https://sourceforge.net/projects/andyyan-gsi/files/
- MisterZtr: https://github.com/MisterZtr/LineageOS_gsi/releases
- TrebleDroid releases: https://github.com/TrebleDroid/treble_experimentations/releases
- bpf loader requirements: https://android.googlesource.com/platform/packages/modules/Connectivity/+/refs/heads/main/bpf/loader/NetBpfLoad.cpp
- Common kernels matrix: https://source.android.com/docs/core/architecture/kernel/android-common
- FCM levels: https://source.android.com/docs/core/architecture/vintf/fcm
- fastbootd: https://source.android.com/docs/core/architecture/bootloader/fastbootd
- InkPalm Plus specs: https://www.cnx-software.com/2022/05/25/150-inkpalm-plus-ereader-features-rk3566-soc-5-84-inch-display/
