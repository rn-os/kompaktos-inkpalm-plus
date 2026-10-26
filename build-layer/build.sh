#!/usr/bin/env bash
# Build a signed InkPalm Plus KompaktOS system image on a Linux x86-64 server.
#
#     build-layer/build.sh [TREE]            (TREE default: ~/inkpalm/lineage)
#
# Follows upstream KompaktOS's own build.sh (https://github.com/gezimos/KompaktOS), whose files
# are used in place from a pinned checkout in $WORK_DIR/kompaktos, never copied into this repo:
#   1 preflight   tools, disk, blobs (extract-blobs.sh), keys (gen-keys.sh)
#   2 upstream    clone/fetch KompaktOS at KOMPAKTOS_REF, verify the commit
#   3 init        repo init LineageOS lineage-23.2 (--git-lfs) + MisterZtr/treble_manifest
#                 as .repo/local_manifests (+ upstream local_manifests/*.xml, none today)
#   4 sync        repo sync with upstream's flags              [stamp; INKPALM_RESYNC=1 forces]
#   5 patch       upstream patches/apply-patches.sh (git am), then ours from
#                 build-layer/patches/inkpalm/<project>/*.patch  [stamp = hash of both series]
#   6 layer       vendor/kompakt (upstream), vendor/inkpalm (ours, symlinks resolved), blobs,
#                 boot animation, keys -> vendor/lineage-priv/keys, APEX keys, file_contexts
#   7 generate    device/phh/treble generate.sh, treble_app build, product identity, inherit
#                 vendor/inkpalm/inkpalm.mk
#   8 build       lunch lineage_arm64_bvN4-bp4a-userdebug (vanilla, ext4); m SystemUI services;
#                 make systemimage                               [make itself is incremental]
#   9 post        raw system.img, checks + fixups of our files, signing report, sha256
# Re-run the same command after a failure: finished stamped stages are skipped.
#
# Signing follows upstream signing.md: keys in vendor/lineage-priv/keys + keys.mk sign every APK
# and APEX at build time; sign_target_files_apks is not used (upstream does not either).
#
# Env (all optional):
#   WORK_DIR=~/inkpalm  KEYS_DIR=~/.inkpalm-keys  BLOBS_DIR=build-layer/blobs  OUT_DIR=$WORK_DIR/out
#   KOMPAKTOS_REF=v1.2  KOMPAKTOS_SHA=<commit, checked when set>  KOMPAKTOS_URL=...
#   TARGET=lineage_arm64_bvN4-bp4a-userdebug  JOBS=$(nproc)
#   INKPALM_RESYNC=1       re-sync the tree (network) even if it was synced before
#   INKPALM_SHALLOW=1      repo init --depth=1 / sync -c (first init only; saves ~100 GB)
#   INKPALM_TEST_KEYS=1    build with the AOSP test keys (no KEYS_DIR needed; not for daily use)
#   INKPALM_FC_INJECT=0    don't add vendor/inkpalm/sepolicy/file_contexts to phh's policy
#   INKPALM_FIXUP=0        only report wrong labels/modes in system.img, don't fix them
#   STRICT_SIGNING=1       fail if any APK is still signed with an AOSP in-tree key
#   STOCK_SYSTEM=<img>     MuditaOS K 1.6.0 system.img: keeps upstream's Mudita charger (useless
#                          on the InkPalm; without it the kpoc_charger module is dropped)
#   PRODUCT_BRAND_ID / PRODUCT_MODEL_ID / PRODUCT_MANUFACTURER_ID   identity (upstream: Mudita /
#                          Kompakt / Mudita, kept by default for parity; phh's Securize copies the
#                          vendor fingerprint over it at boot anyway)
set -euo pipefail
LOG_TAG=build
LAYER=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO=$(cd "$LAYER/.." && pwd)
# shellcheck source=lib/common.sh
. "$LAYER/lib/common.sh"

case "${1:-}" in -h|--help) sed -n '2,41p' "$0"; exit 0 ;; esac

WORK_DIR=${WORK_DIR:-$HOME/inkpalm}
TREE=${1:-${TREE:-$WORK_DIR/lineage}}
KEYS_DIR=${KEYS_DIR:-$HOME/.inkpalm-keys}
BLOBS_DIR=${BLOBS_DIR:-$LAYER/blobs}
OUT_DIR=${OUT_DIR:-$WORK_DIR/out}
JOBS=${JOBS:-$(nproc)}

BRANCH=lineage-23.2
LINEAGE_MANIFEST=https://github.com/LineageOS/android.git
TREBLE_MANIFEST=https://github.com/MisterZtr/treble_manifest.git
KOMPAKTOS_URL=${KOMPAKTOS_URL:-https://github.com/gezimos/KompaktOS.git}
KOMPAKTOS_REF=${KOMPAKTOS_REF:-v1.2}
# v1.2 = the release on the device (checked 2026-10-23). Unset/empty to follow another ref.
if [ "$KOMPAKTOS_REF" = v1.2 ]; then
    KOMPAKTOS_SHA=${KOMPAKTOS_SHA-fa872f92bc9aff69be553af33edf3930ff054271}
else
    KOMPAKTOS_SHA=${KOMPAKTOS_SHA:-}
fi
TARGET=${TARGET:-lineage_arm64_bvN4-bp4a-userdebug}   # vanilla; upstream ships bgN4 (GApps)
PRODUCT=${TARGET%%-*}
INKPALM_RESYNC=${INKPALM_RESYNC:-0}
INKPALM_SHALLOW=${INKPALM_SHALLOW:-0}
INKPALM_TEST_KEYS=${INKPALM_TEST_KEYS:-0}
INKPALM_FC_INJECT=${INKPALM_FC_INJECT:-1}
INKPALM_FIXUP=${INKPALM_FIXUP:-1}
STRICT_SIGNING=${STRICT_SIGNING:-0}
STOCK_SYSTEM=${STOCK_SYSTEM:-}
BRAND_ID=${PRODUCT_BRAND_ID:-Mudita}
MODEL_ID=${PRODUCT_MODEL_ID:-Kompakt}
MANUFACTURER_ID=${PRODUCT_MANUFACTURER_ID:-Mudita}

KDIR=$WORK_DIR/kompaktos
STAMPS=$TREE/.inkpalm-stamps
APK_KEYS="releasekey platform shared media networkstack nfc bluetooth sdk_sandbox testkey"

mkdir -p "$WORK_DIR/logs" "$TREE"
LOG=$WORK_DIR/logs/build-$(date +%Y%m%d-%H%M%S).log
exec > >(tee -a "$LOG") 2>&1
CURRENT=startup
on_exit() {
    local rc=$?
    [ "$rc" -eq 0 ] && return 0
    echo
    warn "failed in stage \"$CURRENT\" (exit $rc). Log: $LOG"
    warn "fix the cause and re-run the same command; finished stages are skipped"
}
trap on_exit EXIT

exec 9> "$WORK_DIR/.build.lock"
flock -n 9 || die "another build.sh is running (lock $WORK_DIR/.build.lock)"

# Commit identity for git am (setup-host.sh normally configures one).
git config user.email >/dev/null 2>&1 || export GIT_COMMITTER_EMAIL=inkpalm-build@localhost GIT_AUTHOR_EMAIL=inkpalm-build@localhost
git config user.name >/dev/null 2>&1 || export GIT_COMMITTER_NAME="InkPalm build" GIT_AUTHOR_NAME="InkPalm build"

# ---- helpers -------------------------------------------------------------------------------
begin() { CURRENT=$1; stage "$1"; }

# Upstream's directory -> project path table, read from its apply-patches.sh, plus ours.
project_map() {
    sed -n 's/^[[:space:]]*\[\([A-Za-z0-9_.-]*\)\]=\([^[:space:]]*\).*/\1 \2/p' "$KDIR/patches/apply-patches.sh"
    sed -e 's/#.*//' -e '/^[[:space:]]*$/d' "$LAYER/patches/inkpalm/projects.map"
}
map_path() { project_map | awk -v n="$1" '$1 == n { print $2; exit }'; }

# Every tree project our build modifies: patched ones, plus the two that generate files.
touched_projects() {
    local d n p
    {
        for d in "$KDIR"/patches/kompakt/*/ "$LAYER"/patches/inkpalm/*/; do
            [ -d "$d" ] || continue
            n=$(basename "$d")
            p=$(map_path "$n")
            [ -n "$p" ] && echo "$p"
        done
        echo device/phh/treble
        echo treble_app
    } | sort -u
}

# Back to the manifest revision, no network: drops git-am'd commits, generated files and our
# file_contexts block, so a changed patch series applies to a clean tree.
reset_touched() {
    local p list=()
    while read -r p; do
        [ -e "$TREE/$p/.git" ] || continue
        git -C "$TREE/$p" am --abort >/dev/null 2>&1 || true
        git -C "$TREE/$p" reset -q --hard
        git -C "$TREE/$p" clean -qfd
        list+=("$p")
    done < <(touched_projects)
    [ ${#list[@]} -eq 0 ] && return 0
    log "resetting ${#list[@]} project(s) to the manifest revision"
    (cd "$TREE" && repo sync -l -d -q -j"$JOBS" "${list[@]}")
}

install_if_changed() {   # src dest: copy only on content change, so mtimes (and ninja) stay put
    if ! cmp -s "$1" "$2"; then mkdir -p "$(dirname "$2")"; cp "$1" "$2"; log "updated ${2#"$TREE"/}"; fi
}

patch_series_hash() {
    {
        echo "kompaktos $(git -C "$KDIR" rev-parse HEAD)"
        find "$LAYER/patches/inkpalm" -type f \( -name '*.patch' -o -name projects.map \) | sort |
            while read -r f; do echo "$(sha256_of "$f") ${f#"$LAYER"/}"; done
    } | sha256sum | cut -d' ' -f1
}

# ---- 1 preflight ---------------------------------------------------------------------------
begin preflight
[ "$(uname -s)-$(uname -m)" = Linux-x86_64 ] || die "needs Linux x86-64 (the AOSP build host)"
[ "$(id -u)" -ne 0 ] || die "do not build as root"
need repo git git-lfs python3 rsync openssl unzip readelf flock sha256sum cmp simg2img e2fsck dumpe2fs
DEBUGFS=$(find_debugfs) || die "debugfs missing (apt install e2fsprogs)"
avail=$(df -BG --output=avail "$TREE" | tail -1 | tr -dc 0-9)
if [ ! -f "$STAMPS/sync" ] && [ "$avail" -lt 300 ]; then
    warn "only ${avail} GB free at $TREE; a first sync + build needs about 250-300 GB"
fi
log "tree $TREE, target $TARGET, $JOBS jobs, ${avail} GB free"

for e in $STOCK_LIBS; do
    [ -s "$BLOBS_DIR/${e%%:*}" ] || die "missing $BLOBS_DIR/${e%%:*}: run build-layer/extract-blobs.sh on your Mac and copy blobs/ here"
done
[ -s "$BLOBS_DIR/bootanimation.zip" ] ||
    die "missing $BLOBS_DIR/bootanimation.zip: extract-blobs.sh --kompakt-system <KompaktOS system.img> (or --bootanim <zip>)"
if [ -f "$BLOBS_DIR/SHA256SUMS" ]; then
    (cd "$BLOBS_DIR" && sha256sum --quiet -c SHA256SUMS) || die "blobs do not match $BLOBS_DIR/SHA256SUMS"
fi

if [ "$INKPALM_TEST_KEYS" = 1 ]; then
    warn "INKPALM_TEST_KEYS=1: signing with the public AOSP test keys"
else
    [ -d "$KEYS_DIR" ] || die "no keys at $KEYS_DIR: run build-layer/gen-keys.sh (or INKPALM_TEST_KEYS=1)"
    KEYS_DIR=$(abs_dir "$KEYS_DIR")
    in_git_tree "$KEYS_DIR" && die "$KEYS_DIR is inside a git work tree; keep keys outside any repo"
    for k in $APK_KEYS; do
        [ -f "$KEYS_DIR/$k.pk8" ] && [ -f "$KEYS_DIR/$k.x509.pem" ] || die "missing $KEYS_DIR/$k.{pk8,x509.pem} (gen-keys.sh)"
    done
    [ -f "$KEYS_DIR/keys.mk" ] || die "missing $KEYS_DIR/keys.mk (gen-keys.sh)"
fi

# ---- 2 upstream ----------------------------------------------------------------------------
begin upstream
if [ ! -d "$KDIR/.git" ]; then
    git clone -q "$KOMPAKTOS_URL" "$KDIR"
fi
[ -z "$(git -C "$KDIR" status --porcelain)" ] || die "$KDIR has local changes; it must stay a pristine upstream checkout"
git -C "$KDIR" fetch -q --tags origin
if git -C "$KDIR" rev-parse -q --verify "refs/remotes/origin/$KOMPAKTOS_REF" >/dev/null; then
    git -C "$KDIR" checkout -q --detach "origin/$KOMPAKTOS_REF"     # a branch: its fetched tip
else
    git -C "$KDIR" checkout -q --detach "$KOMPAKTOS_REF"            # a tag or commit
fi
KSHA=$(git -C "$KDIR" rev-parse HEAD)
if [ -n "$KOMPAKTOS_SHA" ] && [ "$KSHA" != "$KOMPAKTOS_SHA" ]; then
    die "KompaktOS $KOMPAKTOS_REF is $KSHA, expected $KOMPAKTOS_SHA (tag moved? set KOMPAKTOS_SHA= to accept)"
fi
for f in patches/apply-patches.sh vendor/kompakt/kompakt.mk build.sh; do
    [ -f "$KDIR/$f" ] || die "upstream layout changed: no $f"
done
log "KompaktOS $KOMPAKTOS_REF = $KSHA"

# ---- 3 init --------------------------------------------------------------------------------
begin init
cd "$TREE"
if [ ! -d .repo ]; then
    depth=()
    [ "$INKPALM_SHALLOW" = 1 ] && depth=(--depth=1)
    repo init -u "$LINEAGE_MANIFEST" -b "$BRANCH" --git-lfs "${depth[@]}"
fi
# Device projects come from MisterZtr's manifest, used unforked (as upstream does).
if [ ! -d .repo/local_manifests ]; then
    git clone -q "$TREBLE_MANIFEST" .repo/local_manifests -b "$BRANCH"
fi
for x in "$KDIR"/local_manifests/*.xml; do
    if [ -f "$x" ]; then install_if_changed "$x" ".repo/local_manifests/kompaktos-$(basename "$x")"; fi
done

# ---- 4 sync --------------------------------------------------------------------------------
begin sync
mkdir -p "$STAMPS"
if [ -f "$STAMPS/sync" ] && [ "$INKPALM_RESYNC" != 1 ]; then
    log "skip: synced $(cat "$STAMPS/sync") (INKPALM_RESYNC=1 to sync again)"
else
    if [ -f "$STAMPS/sync" ]; then reset_touched; fi
    git -C .repo/local_manifests pull -q --ff-only || warn "could not update .repo/local_manifests"
    cflag=()
    [ "$INKPALM_SHALLOW" = 1 ] && cflag=(-c)
    repo sync --force-sync --optimized-fetch --no-tags --no-clone-bundle --prune -j"$JOBS" "${cflag[@]}"
    rm -f "$STAMPS/patch"
    date -u '+%Y-%m-%dT%H:%MZ' > "$STAMPS/sync"
fi

# ---- 5 patch -------------------------------------------------------------------------------
begin patch
want=$(patch_series_hash)
if [ "$(cat "$STAMPS/patch" 2>/dev/null || true)" = "$want" ]; then
    log "skip: series unchanged since the last successful apply"
else
    rm -f "$STAMPS/patch"
    reset_touched
    log "upstream series: $KDIR/patches/apply-patches.sh"
    if ! bash "$KDIR/patches/apply-patches.sh" "$TREE" | tee "$WORK_DIR/logs/apply-upstream.log" ||
       ! grep -q '^ALL_OK$' "$WORK_DIR/logs/apply-upstream.log"; then
        die "upstream patches did not apply cleanly (FAIL/SKIP lines above; is lineage-23.2 ahead of $KOMPAKTOS_REF?)"
    fi
    n=0
    for d in "$LAYER"/patches/inkpalm/*/; do
        [ -d "$d" ] || continue
        name=$(basename "$d")
        patches=()
        for p in "$d"[0-9]*.patch; do if [ -f "$p" ]; then patches+=("$p"); fi; done
        [ ${#patches[@]} -gt 0 ] || continue
        proj=$(map_path "$name")
        [ -n "$proj" ] || die "patches/inkpalm/$name: no project mapping (add it to patches/inkpalm/projects.map)"
        [ -e "$TREE/$proj/.git" ] || die "patches/inkpalm/$name: $proj is not in the tree"
        log "APPLY $proj (${#patches[@]} InkPalm patch(es))"
        if ! git -C "$TREE/$proj" am --keep-non-patch "${patches[@]}"; then
            git -C "$TREE/$proj" am --abort || true
            die "InkPalm patches for $proj do not apply; rebase them on the synced tree"
        fi
        n=$((n + ${#patches[@]}))
    done
    log "InkPalm patches applied: $n"
    echo "$want" > "$STAMPS/patch"
fi

# ---- 6 layer -------------------------------------------------------------------------------
begin layer
# vendor/kompakt: upstream source, rsync -a so unchanged files keep their mtimes.
rsync -a --delete \
    --exclude /OpenEUICC/ --exclude /kompakt.mk --exclude /charger/Android.bp \
    --exclude /charger/kpoc_charger --exclude /charger/kpoc_charger.mudita --exclude /charger/libshowlogo.so \
    "$KDIR/vendor/kompakt/" "$TREE/vendor/kompakt/"
tmp=$(mktemp)
if [ -n "$STOCK_SYSTEM" ]; then
    cp "$KDIR/vendor/kompakt/kompakt.mk" "$tmp"
    install_if_changed "$KDIR/vendor/kompakt/charger/Android.bp" "$TREE/vendor/kompakt/charger/Android.bp"
    if [ ! -f "$TREE/vendor/kompakt/charger/kpoc_charger" ]; then
        bash "$TREE/vendor/kompakt/charger/extract-from-stock.sh" "$STOCK_SYSTEM"
    fi
else
    # Mudita's MediaTek charging screen cannot run on the rk3566 and its binaries come from a
    # MuditaOS image we don't have: drop the module (upstream's build.sh requires STOCK_SYSTEM).
    # UNVERIFIED: off-mode charging UI. Upstream's device_phh_treble 0006 also disables the AOSP
    # charger in charging mode, so the panel shows no charging screen either way.
    sed '/^PRODUCT_PACKAGES += kpoc_charger$/d' "$KDIR/vendor/kompakt/kompakt.mk" > "$tmp"
    grep -qE '^PRODUCT_PACKAGES.*kpoc_charger' "$tmp" && die "could not drop kpoc_charger from kompakt.mk"
    rm -f "$TREE/vendor/kompakt/charger/Android.bp"
fi
install_if_changed "$tmp" "$TREE/vendor/kompakt/kompakt.mk"
rm -f "$tmp"

# OpenEUICC exactly as upstream pins and patches it (read from its build.sh). Built in a temp
# dir and moved into place, so an interrupted run never leaves a half-prepared clone.
OE_URL=$(sed -n 's/^OPENEUICC_URL=//p' "$KDIR/build.sh")
OE_REV=$(sed -n 's/^OPENEUICC_REV=//p' "$KDIR/build.sh")
if [ ! -d "$TREE/vendor/kompakt/OpenEUICC/.git" ]; then
    [ -n "$OE_URL" ] && [ -n "$OE_REV" ] || die "could not read the OpenEUICC pin from upstream build.sh"
    oe=$TREE/vendor/kompakt/.OpenEUICC.tmp
    rm -rf "$oe"
    if git clone -q "$OE_URL" "$oe"; then
        git -C "$oe" checkout -q "$OE_REV"
        git -C "$oe" submodule update -q --init --recursive
        for diff in "$KDIR"/patches/openeuicc/*.diff; do git -C "$oe" apply "$diff"; done
        cp -a "$KDIR/prebuilts/openeuicc/app-deps/prebuilts" "$oe/app-deps/"
        mv "$oe" "$TREE/vendor/kompakt/OpenEUICC"
        log "OpenEUICC at ${OE_REV:0:12}"
    else
        rm -rf "$oe"
        warn "could not clone OpenEUICC: no eSIM manager in this build (upstream behaves the same)"
    fi
fi

# vendor/inkpalm: ours. -L turns the symlinks to tools/inkcontrol and gsi/vendor-fix into files.
rsync -aL --delete --exclude /blobs/ --exclude /bootanimation/ \
    "$LAYER/vendor/inkpalm/" "$TREE/vendor/inkpalm/"
mkdir -p "$TREE/vendor/inkpalm/blobs" "$TREE/vendor/inkpalm/bootanimation"
for e in $STOCK_LIBS; do
    install_if_changed "$BLOBS_DIR/${e%%:*}" "$TREE/vendor/inkpalm/blobs/${e%%:*}"
done
install_if_changed "$BLOBS_DIR/bootanimation.zip" "$TREE/vendor/inkpalm/bootanimation/bootanimation.zip"

# Keys: vendor/lineage-priv/keys is the path LineageOS and upstream signing.md expect.
if [ "$INKPALM_TEST_KEYS" = 1 ]; then
    rm -rf "$TREE/vendor/lineage-priv/keys"
else
    bash "$LAYER/gen-keys.sh" --apex-from-tree "$TREE" "$KEYS_DIR"   # only adds missing APEX keys
    mkdir -p "$TREE/vendor/lineage-priv"
    rsync -a --delete "$KEYS_DIR/" "$TREE/vendor/lineage-priv/keys/"
    chmod 0700 "$TREE/vendor/lineage-priv" "$TREE/vendor/lineage-priv/keys"
fi

# Our file labels in phh's system policy, between markers (only rewritten on change).
FC=$TREE/device/phh/treble/sepolicy/file_contexts
[ -f "$FC" ] || die "no $FC (device/phh/treble not synced?)"
python3 -I - "$FC" "$TREE/vendor/inkpalm/sepolicy/file_contexts" "$INKPALM_FC_INJECT" <<'PY'
import sys
fc, ours, on = sys.argv[1:4]
B, E = "# >>> inkpalm build-layer (build-layer/build.sh)", "# <<< inkpalm build-layer"
old = open(fc).read()
out, skip = [], False
for line in old.split("\n"):
    if line == B:
        skip = True
    elif line == E:
        skip = False
    elif not skip:
        out.append(line)
new = "\n".join(out).rstrip("\n") + "\n"
if on == "1":
    new += "\n" + B + "\n" + open(ours).read().rstrip("\n") + "\n" + E + "\n"
if new != old:
    open(fc, "w").write(new)
    print("file_contexts: InkPalm block " + ("written" if on == "1" else "removed"))
PY

# ---- 7 generate ----------------------------------------------------------------------------
begin generate
(cd "$TREE/device/phh/treble" && bash generate.sh lineage)
# TrebleApp.apk is not committed upstream; build it from the patched source (as upstream).
(cd "$TREE/treble_app" && bash build.sh release)
# generate.sh sets the brand after the ROM inherit, so rewrite the generated files (as upstream).
for mk in "$TREE"/device/phh/treble/lineage_arm64_*.mk; do
    [ -f "$mk" ] || continue
    python3 -I - "$mk" "$BRAND_ID" "$MODEL_ID" "$MANUFACTURER_ID" <<'PY'
import re, sys
path, brand, model, manu = sys.argv[1:5]
text = open(path).read()
for var, val in (("PRODUCT_BRAND", brand), ("PRODUCT_SYSTEM_BRAND", brand),
                 ("PRODUCT_MODEL", model), ("PRODUCT_SYSTEM_MODEL", model),
                 ("PRODUCT_MANUFACTURER", manu), ("PRODUCT_SYSTEM_MANUFACTURER", manu)):
    text, n = re.subn(r"^%s\s*:=.*$" % var, "%s := %s" % (var, val), text, flags=re.M)
    if not n:
        text = text.rstrip("\n") + "\n%s := %s\n" % (var, val)
open(path, "w").write(text)
PY
done
PMK=$TREE/device/phh/treble/$PRODUCT.mk
[ -f "$PMK" ] || die "generate.sh produced no $PMK (TARGET=$TARGET)"
if ! grep -q 'vendor/inkpalm/inkpalm.mk' "$PMK"; then
    printf '\n# InkPalm Plus layer (build-layer/build.sh); last, so it overrides kompakt.mk.\n$(call inherit-product, vendor/inkpalm/inkpalm.mk)\n' >> "$PMK"
fi
grep -H -E '^PRODUCT_(SYSTEM_)?(BRAND|MODEL|MANUFACTURER)|inkpalm.mk' "$PMK"

# ---- 8 build -------------------------------------------------------------------------------
begin build
export USE_CCACHE=${USE_CCACHE:-1}
export CCACHE_EXEC=${CCACHE_EXEC:-$(command -v ccache || true)}
cd "$TREE"
set +eu +o pipefail
# shellcheck disable=SC1091
source build/envsetup.sh
lunch "$TARGET"
set -eu -o pipefail
[ "${TARGET_PRODUCT:-}" = "$PRODUCT" ] || die "lunch $TARGET failed"
# Compile check SystemUI and services before the full image (as upstream).
m SystemUI services -j"$JOBS"
make systemimage -j"$JOBS"
m apksigner -j"$JOBS" || warn "could not build apksigner; the signing report will be skipped"

# ---- 9 post --------------------------------------------------------------------------------
begin post
POUT=${ANDROID_PRODUCT_OUT:-$(dirname "$(ls -t "$TREE"/out/target/product/*/system.img | head -1)")}
SRC_IMG=$POUT/system.img
[ -f "$SRC_IMG" ] || die "no $SRC_IMG"
RUN=$OUT_DIR/$(date +%Y%m%d-%H%M%S)
mkdir -p "$RUN"
IMG=$RUN/system.img
if [ "$(od -An -tx1 -N4 "$SRC_IMG" | tr -d ' \n')" = 3aff26ed ]; then
    simg2img "$SRC_IMG" "$IMG"          # sparse -> raw (build_super.py and debugfs need raw)
else
    cp "$SRC_IMG" "$IMG"
fi

# Our files in the image: type label mode uid gid path [source to compare]. Labels/modes are
# what gsi/vendor-fix/bake.sh set by hand and what the device has been running.
V=$LAYER/vendor/inkpalm
EXPECT=$(mktemp)
{
    echo "d system_file 0755 0 0 /system/phh/inkpalm"
    echo "d vendor_file 0755 0 0 /system/phh/inkpalm/lib64"
    for e in $STOCK_LIBS; do
        echo "f vendor_file 0644 0 0 /system/phh/inkpalm/lib64/${e%%:*} $BLOBS_DIR/${e%%:*}"
    done
    echo "d vendor_file 0755 0 0 /system/lib64/inkpalm-vfix"
    echo "f vendor_file 0644 0 0 /system/lib64/inkpalm-vfix/libheif.so"
    for s in inkpalm-vfix eink-bridge eink-apply inkpalm-defaults inkpalm-poweroff; do
        echo "f phhsu_exec 0755 0 2000 /system/phh/inkpalm/$s.sh $V/vendor-fix/$s.sh"
    done
    echo "f system_file 0644 0 0 /system/etc/init/inkpalm-vfix.rc $V/init/inkpalm-vfix.rc"
    echo "f system_file 0644 0 0 /system/usr/idc/fts_ts.idc $V/vendor-fix/fts_ts.idc"
    echo "f system_file 0644 0 0 /system/product/overlay/config/config.xml $V/vendor-fix/product-overlay-config.xml"
    # No content compare: LineageOS's bootanimation module may repack the zip (UNVERIFIED).
    echo "f system_file 0644 0 0 /system/product/media/bootanimation.zip"
    echo "f system_file 0644 0 0 /system/product/overlay/InkPalmPowerWake.apk"
    echo "f - - - - /system/priv-app/InkControl/InkControl.apk"
    echo "f - - - - /system/etc/permissions/privapp-permissions-org.neoport.inkcontrol.xml"
    echo "f - - - - /system/etc/sysconfig/initial-package-state_org.neoport.inkcontrol.xml"
} > "$EXPECT"

W=$(mktemp -d)
dfs()  { "$DEBUGFS" -R "$1" "$IMG" 2>/dev/null; }
dfsw() { "$DEBUGFS" -w -R "$1" "$IMG" >/dev/null 2>&1; }
problems=0; fixes=()
while read -r type label mode uid gid path src; do
    st=$(dfs "stat $path")
    if ! grep -q '^Inode:' <<< "$st"; then
        warn "MISSING in system.img: $path"; problems=$((problems + 1)); continue
    fi
    if [ -n "${src:-}" ]; then
        rm -f "$W/f"; dfs "dump -p $path $W/f" >/dev/null
        if [ "$(sha256_of "$W/f")" != "$(sha256_of "$src")" ]; then
            warn "CONTENT differs from ${src#"$REPO"/}: $path (an earlier PRODUCT_COPY_FILES entry won?)"
            problems=$((problems + 1))
        fi
    fi
    [ "$label" = - ] && continue
    rm -f "$W/l"; dfs "ea_get -f $W/l $path security.selinux" >/dev/null
    have_label=$(tr -d '\0' < "$W/l" 2>/dev/null || true)
    have_mode=$(sed -n 's/.*Mode: *\([0-7]*\).*/\1/p' <<< "$st" | head -1)
    have_ids=$(sed -n 's/^User: *\([0-9]*\) *Group: *\([0-9]*\).*/\1 \2/p' <<< "$st" | head -1)
    [ "$have_label" = "u:object_r:$label:s0" ] || fixes+=("label $path u:object_r:$label:s0 (was ${have_label:-none})")
    [ "$have_mode" = "$mode" ] || fixes+=("mode $path $type$mode (was $have_mode)")
    [ "$have_ids" = "$uid $gid" ] || fixes+=("owner $path $uid $gid (was $have_ids)")
done < "$EXPECT"

# libheif stub sanity: soname and the one symbol libskia imports.
rm -f "$W/heif"; dfs "dump -p /system/lib64/inkpalm-vfix/libheif.so $W/heif" >/dev/null
if [ -s "$W/heif" ]; then
    readelf -d "$W/heif" | grep -q 'SONAME.*\[libheif.so\]' || { warn "libheif stub: soname is not libheif.so"; problems=$((problems + 1)); }
    readelf -W --dyn-syms "$W/heif" | grep -q ' _Z17createHeifDecoderv$' || { warn "libheif stub: createHeifDecoder() not exported"; problems=$((problems + 1)); }
fi

if [ ${#fixes[@]} -gt 0 ]; then
    for f in "${fixes[@]}"; do log "needs fixup: $f"; done
    if [ "$INKPALM_FIXUP" = 1 ]; then
        dumpe2fs -h "$IMG" 2>/dev/null | grep -i '^Filesystem features' | grep -q shared_blocks &&
            die "system.img uses ext4 shared_blocks (read-only); cannot fix up. Build with INKPALM_FC_INJECT=1 working, or BOARD_EXT4_SHARE_DUP_BLOCKS off"
        for f in "${fixes[@]}"; do
            # "<what> <path> <value...> (was ...)"; paths and labels contain no spaces.
            # shellcheck disable=SC2086
            set -- $f
            case "$1" in
                label) printf '%s\0' "$3" > "$W/label"; dfsw "ea_set -f $W/label $2 security.selinux" ;;
                mode)  m=$3   # d0755 -> 040755, f0644 -> 0100644 (inode type bits + permissions)
                       case "$m" in d*) m=040${m:2} ;; f*) m=0100${m:2} ;; esac
                       dfsw "set_inode_field $2 mode $m" ;;
                owner) dfsw "set_inode_field $2 uid $3"; dfsw "set_inode_field $2 gid $4" ;;
            esac
        done
        e2fsck -fn "$IMG" >/dev/null 2>&1 || die "e2fsck reports problems after the fixups"
        log "applied ${#fixes[@]} fixup(s) with debugfs (bake.sh's method); fsck clean"
    else
        problems=$((problems + ${#fixes[@]}))
    fi
fi
[ "$problems" -eq 0 ] || die "$problems problem(s) with the InkPalm files in system.img (see above)"
log "InkPalm files in system.img: all present, content/labels/modes OK"

# Signing report (upstream signing.md's checks, generalised).
APKSIGNER=$(command -v apksigner || echo "$TREE/out/host/linux-x86/bin/apksigner")
if [ -x "$APKSIGNER" ]; then
    ours=$W/ours; : > "$ours"
    if [ "$INKPALM_TEST_KEYS" != 1 ]; then
        for pem in "$KEYS_DIR"/*.x509.pem; do
            openssl x509 -in "$pem" -outform DER | sha256sum | cut -d' ' -f1 >> "$ours"
        done
        platform_digest=$(openssl x509 -in "$KEYS_DIR/platform.x509.pem" -outform DER | sha256sum | cut -d' ' -f1)
    fi
    n_ours=0; n_aosp=0; n_other=0; aosp_list=(); other_list=()
    while read -r apk; do
        out=$("$APKSIGNER" verify --print-certs "$apk" 2>/dev/null || true)
        dg=$(sed -n 's/^Signer #1 certificate SHA-256 digest: //p' <<< "$out" | head -1)
        if [ -n "$dg" ] && grep -qx "$dg" "$ours"; then n_ours=$((n_ours + 1))
        elif grep -q 'android@android.com' <<< "$out"; then n_aosp=$((n_aosp + 1)); aosp_list+=("${apk#"$POUT"/}")
        else n_other=$((n_other + 1)); other_list+=("${apk#"$POUT"/}"); fi
    done < <(find "$POUT/system" "$POUT/apex" -name '*.apk' 2>/dev/null)
    log "APKs: $n_ours with our keys, $n_aosp with AOSP in-tree keys, $n_other other (presigned prebuilts)"
    for a in "${aosp_list[@]}"; do warn "AOSP key: $a -> add <module>:inkpalm-releasekey to PRODUCT_CERTIFICATE_OVERRIDES in keys.mk"; done
    for a in "${other_list[@]}"; do log "presigned/other: $a"; done
    if [ "$INKPALM_TEST_KEYS" != 1 ]; then
        ic=$(dfs "dump -p /system/priv-app/InkControl/InkControl.apk $W/ic.apk" >/dev/null; "$APKSIGNER" verify --print-certs "$W/ic.apk" 2>/dev/null | sed -n 's/^Signer #1 certificate SHA-256 digest: //p' | head -1)
        if [ -n "$ic" ] && [ "$ic" = "$platform_digest" ]; then
            log "InkControl is signed with our platform key"
        else
            warn "InkControl is NOT signed with our platform key"; problems=$((problems + 1))
        fi
        # APEX payload keys vs ours (signing.md: missing keys silently fall back to AOSP's).
        : > "$W/apexkeys"
        for k in "$KEYS_DIR"/*.avbpubkey; do [ -f "$k" ] && sha256_of "$k" >> "$W/apexkeys"; done
        a_ours=0; a_other=()
        for ap in "$POUT"/system/apex/*.apex "$POUT"/system/apex/*.capex; do
            [ -f "$ap" ] || continue
            rm -f "$W/a.apex"
            case "$ap" in *.capex) unzip -p "$ap" original_apex > "$W/a.apex" ;; *) cp "$ap" "$W/a.apex" ;; esac
            pk=$(unzip -p "$W/a.apex" apex_pubkey 2>/dev/null | sha256sum | cut -d' ' -f1)
            if grep -qx "$pk" "$W/apexkeys"; then a_ours=$((a_ours + 1)); else a_other+=("$(basename "$ap")"); fi
        done
        log "APEX payloads: $a_ours with our keys, ${#a_other[@]} other"
        for a in "${a_other[@]}"; do warn "APEX not signed with our payload key: $a"; done
    fi
    if [ "$STRICT_SIGNING" = 1 ] && [ "$n_aosp" -gt 0 ]; then die "STRICT_SIGNING=1 and $n_aosp APK(s) use AOSP keys"; fi
    [ "$problems" -eq 0 ] || die "signing check failed (see above)"
else
    warn "no apksigner: signing report skipped"
fi

# Outputs.
(cd "$RUN" && sha256sum system.img > system.img.sha256)
(cd "$TREE" && repo manifest -r -o "$RUN/manifest-pinned.xml")
cp "$BLOBS_DIR/SHA256SUMS" "$RUN/blobs.SHA256SUMS" 2>/dev/null || true
{
    echo "built:      $(date -u '+%Y-%m-%dT%H:%MZ') on $(hostname)"
    echo "target:     $TARGET"
    echo "kompaktos:  $KOMPAKTOS_REF $KSHA"
    echo "layer:      $(git -C "$REPO" rev-parse HEAD 2>/dev/null || echo unknown)$(git -C "$REPO" diff --quiet 2>/dev/null || echo ' (dirty)')"
    echo "synced:     $(cat "$STAMPS/sync")"
    if [ "$INKPALM_TEST_KEYS" = 1 ]; then echo "keys:       AOSP test keys"
    else
        echo "releasekey: $(openssl x509 -in "$KEYS_DIR/releasekey.x509.pem" -outform DER | sha256sum | cut -d' ' -f1)"
        echo "platform:   $(openssl x509 -in "$KEYS_DIR/platform.x509.pem" -outform DER | sha256sum | cut -d' ' -f1)"
    fi
    echo "fixups:     ${#fixes[@]}"
} > "$RUN/build-info.txt"
ln -sfn "$RUN" "$OUT_DIR/latest"
rm -rf "$W" "$EXPECT"
CURRENT=done
echo
log "image:   $IMG ($(stat -c %s "$IMG") bytes)"
log "sha256:  $(cut -d' ' -f1 "$RUN/system.img.sha256")"
log "info:    $RUN/build-info.txt, manifest-pinned.xml"
log "next:    copy system.img + system.img.sha256 to your Mac and flash (build-layer/README.md)"
