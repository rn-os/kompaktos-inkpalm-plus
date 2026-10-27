#!/bin/zsh
# Install / update InkPalm+ (com.inkpalmplus) on the rooted KompaktOS GSI, then run the post-install check.
#
#   tools/install-inkpalmplus.sh [--serial SERIAL] [latest | <tag> | <path.apk>]
#
#   latest (default)  newest release OR pre-release of rn-os/inkpalm-plus (gh release download) into a
#                     NEW empty dir under ${TMPDIR:-/tmp}
#   <tag>             that release tag, e.g. 1.1.0-dev.37
#   <path.apk>        a local APK
# Steps: signer check (REFUSES on a different signer: that would need an uninstall, which wipes the
# app's data; this script never uninstalls) -> `adb install -r --no-incremental` -> rebind the
# accessibility service if it is not bound -> Doze whitelist + WRITE_SECURE_SETTINGS + WRITE_SETTINGS
# ensured -> tools/regress.sh --quick (its exit status is ours).
# Exit: 0 ok, 1 install/check failed or quick check had a FAIL, 2 usage/no device, 3 signer mismatch / not rooted.

SCRIPT_DIR=${0:A:h}
. $SCRIPT_DIR/lib/inkpalmplus.sh
REPO_GH=rn-os/inkpalm-plus
APP=com.inkpalmplus
SVC_SHORT=$APP/.QuickPanelService
SVC_FULL=$APP/$APP.QuickPanelService
SERIAL=""; SRC=latest

while (( $# )); do
  case $1 in
    --serial) SERIAL=$2; shift 2;;
    -h|--help) sed -n '2,15p' $0; exit 0;;
    -*) print -u2 "unknown arg $1"; exit 2;;
    *) SRC=$1; shift;;
  esac
done
ADB=(adb); [[ -n $SERIAL ]] && { ADB+=(-s $SERIAL); export ANDROID_SERIAL=$SERIAL; }
adbt() { local t=$1; shift; perl -e 'alarm shift; exec @ARGV' $t "${ADB[@]}" "$@" </dev/null; }
sh_()  { adbt 25 shell "$1" 2>&1 | tr -d '\r'; }
die()  { print -u2 "install-inkpalmplus: $*"; exit ${2:-1}; }

adbt 10 get-state 2>/dev/null | grep -q device || die "no adb device (if adb hangs: adb kill-server; adb start-server)" 2
[[ $(sh_ "id -u" | tail -1) == 0 ]] || die "adb is not root (run: adb root)" 3
ipp_apksigner >/dev/null || die "no apksigner found (install Android build-tools or set ANDROID_HOME)" 2

# ---- 1. get the APK
if [[ -f $SRC ]]; then
  APK=${SRC:A}
else
  command -v gh >/dev/null || die "gh not found (needed to download a release)" 2
  TAG=$SRC
  if [[ $SRC == latest ]]; then
    TAG=$(perl -e 'alarm shift; exec @ARGV' 60 gh release list -R $REPO_GH --limit 1 --json tagName -q '.[0].tagName' </dev/null) \
      && [[ -n $TAG ]] || die "cannot list releases of $REPO_GH (gh auth?)" 2
  fi
  DL=$(mktemp -d "${TMPDIR:-/tmp}/inkpalmplus.XXXXXX") || die "cannot create a temp dir" 2
  print "downloading $REPO_GH $TAG -> $DL"
  perl -e 'alarm shift; exec @ARGV' 180 gh release download $TAG -R $REPO_GH --pattern '*.apk' --dir $DL </dev/null \
    || die "gh release download $TAG failed" 2
  APKS=($DL/*.apk(N))
  (( ${#APKS} >= 1 )) || die "release $TAG has no .apk asset" 2
  (( ${#APKS} == 1 )) || print "NOTE: ${#APKS} apks in the release, using ${APKS[1]:t}: ${(j: :)APKS:t}"
  APK=${APKS[1]}
fi
print "apk: $APK"

# ---- 2. signer safety check
NEWSG=$(ipp_apk_signer $APK)
[[ -n $NEWSG ]] || die "cannot read the signer of $APK: refusing to install" 3
print "new apk signer SHA-256:       $NEWSG"
INST=$(sh_ "pm path $APP" | head -1 | sed 's/^package://')
if [[ -n $INST ]]; then
  TMPD=$(mktemp -d "${TMPDIR:-/tmp}/inkpalmplus-cur.XXXXXX"); trap 'rm -rf $TMPD' EXIT
  adbt 60 pull $INST $TMPD/cur.apk >/dev/null 2>&1
  CURSG=$(ipp_apk_signer $TMPD/cur.apk)
  [[ -n $CURSG ]] || die "cannot read the installed app's signer: refusing to install" 3
  print "installed app signer SHA-256: $CURSG"
  if [[ $CURSG != $NEWSG ]]; then
    cat >&2 <<EOM
REFUSING: the APK is signed with a different key than the installed InkPalm+.
Android would only accept it after an uninstall, and an uninstall WIPES the app's data
(settings, AOD face, sleep/power-off pictures). This script never uninstalls.
To switch keys deliberately: note/back up what you need from the app, then yourself run
    adb uninstall $APP
and run this script again (it will do a fresh install). Enable the accessibility service
afterwards if the check below says it is not.
EOM
    exit 3
  fi
else
  print "InkPalm+ is not installed: fresh install"
fi

# ---- 3. install
print "adb install -r --no-incremental ..."
OUT=$(adbt 180 install -r --no-incremental $APK 2>&1 | tr -d '\r'); print -r -- $OUT
[[ $OUT == *Success* ]] || die "adb install failed" 1
sleep 3

# ---- 4. accessibility service: enabled AND bound
a11y_bound() { sh_ "dumpsys accessibility" | awk '/Bound services:/{b=1} /Enabled services:/{b=0} b' | grep -q 'InkPalm+ quick panel'; }
if a11y_bound; then print "accessibility service bound"
else
  print "accessibility service not bound: rebinding"
  CUR=$(sh_ "settings get secure enabled_accessibility_services" | tail -1); [[ $CUR == null ]] && CUR=""
  ENTRIES=(${(s.:.)CUR}); KEEP=(); MINE=""
  for e in $ENTRIES; do
    if [[ $e == $SVC_SHORT || $e == $SVC_FULL ]]; then MINE=$e; else KEEP+=$e; fi
  done
  [[ -n $MINE ]] || MINE=$SVC_FULL
  # remove only our entry (order and spelling of the others untouched), then add it back at the end,
  # which is where Android appends a newly enabled service
  sh_ "settings put secure enabled_accessibility_services '${(j.:.)KEEP}'" >/dev/null
  sleep 2
  if (( ${#KEEP} )); then sh_ "settings put secure enabled_accessibility_services '${(j.:.)KEEP}:$MINE'" >/dev/null
  else sh_ "settings put secure enabled_accessibility_services '$MINE'" >/dev/null; fi
  bound=0
  for i in {1..15}; do a11y_bound && { bound=1; break; }; sleep 1; done
  (( bound )) && print "accessibility service bound after ${i} s" \
              || print "WARN: still not bound after 15 s (the quick check below will FAIL on a11y_bound)"
fi

# ---- 5. whitelist + grants
sh_ "dumpsys deviceidle whitelist" | grep -q ",$APP," || { print "Doze whitelist: adding $APP"; sh_ "cmd deviceidle whitelist +$APP" >/dev/null; }
sh_ "dumpsys package $APP" | grep -q 'android.permission.WRITE_SECURE_SETTINGS: granted=true' \
  || { print "granting WRITE_SECURE_SETTINGS"; sh_ "pm grant $APP android.permission.WRITE_SECURE_SETTINGS" >/dev/null; }
sh_ "appops get $APP WRITE_SETTINGS" | grep -q 'WRITE_SETTINGS: allow' \
  || { print "appops WRITE_SETTINGS allow"; sh_ "appops set $APP WRITE_SETTINGS allow" >/dev/null; }

# ---- 6. post-install check
print "running tools/regress.sh --quick"
exec $SCRIPT_DIR/regress.sh --quick ${SERIAL:+--serial $SERIAL}
