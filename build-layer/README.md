# build-layer: our own signed KompaktOS build for the InkPalm Plus

A thin layer on top of upstream [KompaktOS](https://github.com/gezimos/KompaktOS) that builds
the KompaktOS system image from source **with the InkPalm fixes built in** and **signed with
our own keys**, instead of baking fixes into someone else's release image
(`gsi/vendor-fix/bake.sh`). Nothing upstream is copied into this repo: `build.sh` checks out
upstream at a pinned tag (default `v1.2`, the release on the device) and uses its patch series,
`apply-patches.sh` and `vendor/kompakt` in place.

**Status: scaffold, never run.** Written without a lineage-23.2 tree; every build-system detail
that could not be checked is marked `UNVERIFIED` in the files and listed at the end.

```
build-layer/
  setup-host.sh       Ubuntu 24.04 server: build deps, repo, git identity, ccache
  gen-keys.sh         your signing keys, outside any git tree (default ~/.inkpalm-keys)
  extract-blobs.sh    6 stock Android 11 libs + boot animation from YOUR backup -> blobs/ (gitignored)
  build.sh            sync, upstream patches, our patches, layers, build, checks, sha256
  lib/common.sh       shared helpers
  patches/inkpalm/    our patch series per project (empty for now; format in its README)
  vendor/inkpalm/     the InkPalm product layer (copied into the tree as vendor/inkpalm)
```

## What the build adds on top of KompaktOS (was: bake.sh)

| bake.sh step | build-layer | on the device |
|---|---|---|
| stock libskia & co. | `Android.mk` prebuilts from `blobs/` | `/system/phh/inkpalm/lib64/*.so` (vendor_file) |
| stub libheif (hand-built with clang) | `cc_library_shared libheif_inkpalm_stub` from `gsi/vendor-fix/heif_stub.c` | `/system/lib64/inkpalm-vfix/libheif.so` |
| `inkpalm-vfix.rc` | `vendor/inkpalm/init/inkpalm-vfix.rc` (variant: one more overlay layer for the Soong-built stub) | `/system/etc/init/inkpalm-vfix.rc` |
| vfix / bridge / apply / defaults scripts | `Android.mk`, sources symlinked from `gsi/vendor-fix/` | `/system/phh/inkpalm/*.sh` (phhsu_exec, 0755) |
| `fts_ts.idc` | `PRODUCT_COPY_FILES` | `/system/usr/idc/fts_ts.idc` |
| gesture-nav overlay config | `PRODUCT_COPY_FILES` | `/system/product/overlay/config/config.xml` |
| `BOOTANIM=` | `TARGET_BOOTANIMATION` (overrides kompakt.mk) | `/system/product/media/bootanimation.zip` |
| InkControl installed by hand | `android_app InkControl`, `certificate: "platform"`, `privileged: true`, privapp + initial-package-state XMLs | `/system/priv-app/InkControl` |

Labels and modes: `vendor/inkpalm/sepolicy/file_contexts` is injected into phh's policy, and
`build.sh` reads every file above back out of `system.img` (content, label, mode, owner). If the
build got a label or mode wrong it fixes it with debugfs exactly as bake.sh did
(`INKPALM_FIXUP=1`, default) and says so in the log and in `build-info.txt`.

The root e-ink bridge (`eink-bridge.sh`) is **transitional**: with InkControl platform-signed it
can set `sys.eink.*` itself. The bridge stays for the frontlight (`/proc/aw99703*`) and the sleep
image until sepolicy lets `platform_app` do that (TODO in `vendor/inkpalm/sepolicy/file_contexts`
and `init/inkpalm-vfix.rc`).

> **Known gap, fix before the first real build:** InkControl only offers the frontlight and the
> sleep screen when its e-ink backend is `bridge` (`Light.java:24`, `SleepScreen.java:28` check
> `"bridge".equals(Eink.backend())`). Platform-signed, the backend becomes `direct`, so both
> features would disappear. They should test `Eink.bridgeAvailable()` (the bridge script exists)
> instead. Not changed here (app code is outside this layer).

## Server

- x86-64 Linux, **Ubuntu 24.04**, 16+ cores, 64 GB RAM, 500 GB NVMe (first sync + build use about
  250-300 GB; `INKPALM_SHALLOW=1` on the first run saves roughly 100 GB, UNVERIFIED figure).
- A normal user with sudo. First sync: hours. First build: about 1.5-3 h on 16 cores
  (estimate); later builds 10-40 min (upstream's figure).
- Run long commands inside `tmux` so an SSH drop does not kill them.

## Step by step

### 1. Provision (server)
```sh
git clone <this repo> ~/InkPalm-KompaktOS        # or rsync it from the Mac
cd ~/InkPalm-KompaktOS
bash build-layer/setup-host.sh
. ~/.profile
```

### 2. Keys (server, once)
```sh
bash build-layer/gen-keys.sh                      # -> ~/.inkpalm-keys (0700), outside any repo
```
APK/platform keys, `keys.mk` and an `Android.bp` with the `inkpalm-releasekey` certificate
module. APEX payload keys need a synced tree; `build.sh` creates them before the first build.
**Back up `~/.inkpalm-keys` off the server** (and again after the first build, which adds the
APEX keys). Lose them and the next build with new keys needs a data wipe. Keys never enter git;
the server is rented, so delete them from it (`shred`) when you stop using it.

### 3. Blobs (Mac, once)
```sh
build-layer/extract-blobs.sh \
    --super ~/InkPalm-Backup/partitions-full/super.img \
    --bootanim ~/InkPalm-Images/kompaktos/bootanim/bootanimation-720x1440.zip
#   (or --kompakt-system ~/InkPalm-Images/kompaktos/vanilla/system.img to take and rescale it)
rsync -av build-layer/blobs/ <server>:InkPalm-KompaktOS/build-layer/blobs/
```
Needs Homebrew e2fsprogs (`debugfs`) and Pillow (boot animation rescale). Tested on the Mac
against the real backup: the six libs come out byte-identical to the ones the device runs
(`~/InkPalm-Images/stock-libs`). Alternatives:
`--from-dir ~/InkPalm-Images/stock-libs` for libs you already extracted, `--bootanim <zip>`.
The libs are Moaan/Rockchip/Google binaries from your own device: `blobs/` is gitignored and
must never be committed or published.

### 4. Sync + build + sign (server)
```sh
tmux new -s build
bash build-layer/build.sh                         # tree in ~/inkpalm/lineage
```
Signing happens during the build (upstream's method, `signing.md`): the keys are copied into
`$TREE/vendor/lineage-priv/keys`, `keys.mk` sets `PRODUCT_DEFAULT_DEV_CERTIFICATE`, every APK
and APEX is signed with them, and the build reports `release-keys`. `sign_target_files_apks` is
not used (upstream does not either).

After the build `build.sh` prints a signing report: APKs signed with our keys, APKs still on an
AOSP in-tree key (upstream found ten on lineage-23.2), presigned prebuilts, APEX payloads not on
our keys, and whether InkControl carries our platform key. For each "AOSP key" APK add
`<module>:inkpalm-releasekey` to `PRODUCT_CERTIFICATE_OVERRIDES` in `~/.inkpalm-keys/keys.mk`
and re-run (`STRICT_SIGNING=1` makes that a hard failure).

Output in `~/inkpalm/out/<date>/` (and `out/latest`): raw ext4 `system.img`,
`system.img.sha256`, `manifest-pinned.xml` (exact revisions of every project, for a reproducible
rebuild), `build-info.txt`, `blobs.SHA256SUMS`.

Re-running: `build.sh` is idempotent. Sync runs once (`INKPALM_RESYNC=1` to update LineageOS),
patches are re-applied only when upstream's or our series changed (it then resets the touched
projects to the manifest revision, which discards manual edits there), the rest is incremental.
`build.sh --help` lists every knob (`INKPALM_TEST_KEYS=1` for a quick test-keys build, etc.).

### 5. Flash (Mac)
```sh
scp '<server>:inkpalm/out/latest/system.img*' ~/InkPalm-Images/kompaktos/own/
cd ~/InkPalm-Images/kompaktos/own && shasum -a 256 -c system.img.sha256
adb reboot fastboot
fastboot getvar is-userspace        # yes
fastboot getvar current-slot        # b
fastboot flash system_b system.img
fastboot erase metadata             # ONLY the first time you switch keys, see below
fastboot -w                         #   (same pair as docs/FLASH-KOMPAKTOS.md)
fastboot reboot
```
Or build a whole super with `tools/build_super.py` and follow `docs/FLASH-KOMPAKTOS.md`.
Revert: `docs/REVERT.md`.

### One-time data wipe when switching keys
The device runs KompaktOS signed with upstream's keys. Our build has a different **platform
key**, so every system app, the `android.uid.system` shared user and the APEXes change
signature; Android refuses the existing `/data` for them (boot loop or broken system apps), and
InkControl is now a system app with a different signature than the copy you sideloaded.
So the **first** flash of our build needs `fastboot -w`:
1. Back up first (`~/InkPalm-Backup` routine: sdcard, Android/data, app exports).
2. Flash as above **with** `fastboot -w`, set up again, restore.
3. Later builds signed with the same keys flash **without** a wipe.
The same applies when going back to upstream-signed KompaktOS, or after losing your keys.

## Reproducing with your own keys (other InkPalm Plus owners)
1. Own device backup: a stock `super.img` dump (see `tools/backup_stock_partitions.sh`), and a
   KompaktOS 1.2 vanilla `system.img` (upstream release) for the boot animation.
2. `extract-blobs.sh` on your machine, copy `blobs/` to your server.
3. `setup-host.sh`, then `gen-keys.sh` with your own subject:
   `KEY_SUBJECT='/C=../O=you/CN=you' bash build-layer/gen-keys.sh`.
4. `build.sh`. Compare `build-info.txt` and `manifest-pinned.xml` with ours if you want to know
   whether you built the same thing; the image itself differs (keys, timestamps).
5. Flash with the one-time wipe above.
Nobody needs our keys, and nothing in this repo is device-unique or proprietary.

## How it maps to upstream's build.sh

| upstream `build.sh` | here |
|---|---|
| `repo init lineage-23.2 --git-lfs`, MisterZtr `treble_manifest` as local manifest | same, plus upstream `local_manifests/*.xml` (none today) |
| `repo sync --force-sync --optimized-fetch --no-tags --no-clone-bundle --prune` | same flags, once (resumable) |
| `patches/apply-patches.sh` | same script, from the pinned checkout; then `patches/inkpalm/` |
| `cp -a vendor/kompakt` | `rsync -a` (keeps mtimes); `kpoc_charger` dropped unless `STOCK_SYSTEM` is given (Mudita binary, MediaTek-only) |
| OpenEUICC clone + patch + prebuilts | same pin, read from upstream's build.sh |
| `generate.sh lineage`, `treble_app/build.sh release`, brand rewrite | same; then `inherit-product vendor/inkpalm/inkpalm.mk` appended |
| `lunch lineage_arm64_bgN4-bp4a-userdebug` (GApps) | `lineage_arm64_bvN4-bp4a-userdebug` (vanilla) |
| `m SystemUI services`, `make systemimage` | same, plus `m apksigner` for the report |
| keys in `vendor/lineage-priv/keys` | copied there from `~/.inkpalm-keys` |

## UNVERIFIED (nothing here has been built yet)
- All Soong/Make specifics of `vendor/inkpalm` on lineage-23.2: `cc_library_shared` with
  `nocrt`/`system_shared_libs: []`, `android_app` with `platform_apis` + `target_sdk_version: "30"`,
  `LOCAL_MODULE_PATH` for ETC prebuilts. `PRODUCT_COPY_FILES` precedence should not matter:
  the upstream 1.2 vanilla `system.img` has no `/system/usr/idc/fts_ts.idc` and no
  `/system/product/overlay/config/config.xml` (checked with debugfs); the post-build content
  check catches a loss anyway.
- That phh's sepolicy tests accept `vendor_file` on `/system/...` paths (`INKPALM_FC_INJECT=0`
  falls back to the debugfs fixup). The fixup needs an image without ext4 `shared_blocks`; the
  upstream 1.2 vanilla image has none (checked), so a build from the same tree should not either.
- The three-layer `/vendor/lib64` overlay (the two-layer one is proven on the device).
- `repo sync -l -d <paths>` discarding git-am'd commits on detached projects (repo's documented
  behaviour, not tested here).
- `gen-keys.sh --apex-from-tree`: that apex_key `private_key`/`public_key` file names looked up
  in the certificate dir are all that is needed (upstream signing.md describes it that way); APEX
  *container* certificates declared per module are not overridden.
- Upstream's own clean-checkout behaviour around `vendor/kompakt/bootanimation/bootanimation.zip`
  (gitignored upstream; overridden here) and OpenEUICC.
- Package names in `setup-host.sh` on 24.04 and the disk/time figures.
