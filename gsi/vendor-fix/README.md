# Making the InkPalm's vendor display stack work on a GSI

**Result (2026-10-23):** AndyYan LineageOS 21 (Android 14) `arm64_bvN` booted to the setup
wizard on the InkPalm Plus via DSU, drawn by Moaan's own e-ink HWC, once the HWC could load.

Problem: `/vendor/lib64/hw/hwcomposer.rk30board.so` links `libskia.so`, a *system* library
in stock Android 11 that GSIs don't ship → composer + SurfaceFlinger crash-loop, panel keeps
showing the boot logo.

Fix = 7 libraries visible in the vendor namespace (`/vendor/lib64`):
- stock Android 11 `libskia.so`, `libdng_sdk.so`, `libft2.so` (from stock `/system/lib64`)
- stock `libandroidicu.so`, `libicuuc.so`, `libicui18n.so` (stock `/system/apex/com.android.art.release/lib64`)
- **stub `libheif.so`** built from `heif_stub.c` (libskia imports only `createHeifDecoder()`;
  the real libheif drags in Android 11 libmedia/libaudioclient/libgui, which then fail on
  symbols). Build: `clang -target aarch64-linux-android30 -O2 -fPIC -ffreestanding
  -fno-stack-protector -c heif_stub.c && ld.lld -shared -soname libheif.so -o libheif.so heif_stub.o`

Tested live with `tools/dsu_tryfix.sh` (tmpfs + overlay over /vendor/lib64, SELinux permissive,
this boot only). Next: bake these into the GSI image so no live hack / permissive is needed.
Proprietary stock libs are NOT committed; they come from the user's own device.

## Touch (fts_ts)
The FocalTech panel reports X 0..1439 / Y 0..719 (protocol A multitouch): it is mounted
rotated relative to the 720x1440 portrait display (raw X = screen y, raw Y = 719 - screen x).
Stock fixed this in its own system partition; the GSI has no IDC for it, so taps land in the
wrong place. `fts_ts.idc` (`touch.orientation = ORIENTATION_270`) fixes it — verified on device
(raw 972,32 -> screen 687,972). Baked to /system/usr/idc/fts_ts.idc.
