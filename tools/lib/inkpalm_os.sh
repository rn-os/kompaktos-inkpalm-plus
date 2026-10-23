# Shared OS detection + guards for InkPalm tools (source from zsh or sh; no side effects on load).
#
# Rules (do NOT rely on ro.product.name / ro.build.fingerprint: phh/TrebleDroid spoofs them to the
# vendor's rockchip/rk3566_eink values on the GSI; KompaktOS spoofs ro.system.build.fingerprint too):
#   GSI         : ro.lineage.version non-empty (checked first; never stock), or else the system
#                 fingerprint looks like a GSI (lineage|tdgsi|treble|phh|gsi|generic|mudita)
#     dsu-gsi     : GSI and ro.gsid.image_running=1 (or `gsi_tool status` says running)
#     flashed-gsi : GSI otherwise
#   stock       : no ro.lineage.version and ro.system.build.fingerprint (fallback ro.build.fingerprint)
#                 contains rockchip/Moaan
#   unreadable  : no lineage version and no system/build fingerprint (device offline, adbd restarting)
#   unknown     : fingerprint readable but neither Moaan nor GSI-looking
# A non-empty system fingerprint without "rockchip/Moaan" is never "stock".

# ip_classify <sys_fp> <build_fp> <gsid_running> <gsi_tool_running 0|1> [lineage_version] -> prints class
ip_classify() {
  local sfp=${1:-} bfp=${2:-} gsid=${3:-} gtool=${4:-0} lin=${5:-} fp l
  fp=$sfp; [ -n "$fp" ] || fp=$bfp
  if [ -n "$lin" ]; then l=gsi
  else
    [ -n "$fp" ] || { echo unreadable; return; }
    l=$(printf '%s' "$fp" | tr 'A-Z' 'a-z')
    case $l in
      *rockchip/moaan*) echo stock; return;;
    esac
  fi
  case $l in
    *lineage*|*tdgsi*|*treble*|*phh*|*gsi*|*generic*|*mudita*)
      if [ "$gsid" = 1 ] || [ "$gtool" = 1 ]; then echo dsu-gsi; else echo flashed-gsi; fi;;
    *) echo unknown;;
  esac
}

# ip_adb_prop <prop> : getprop with up to 5 retries (adbd may be restarting); prints value (maybe empty)
ip_adb_prop() {
  local v i=0
  while [ $i -lt 5 ]; do
    v=$(adb shell getprop "$1" 2>/dev/null | tr -d '\r')
    [ -n "$v" ] && { printf '%s\n' "$v"; return 0; }
    i=$((i+1)); adb wait-for-device >/dev/null 2>&1; sleep 1
  done
  return 1
}

# ip_adb_class : classify the connected device using adb (prints class)
ip_adb_class() {
  local sfp bfp gsid lin gt=0
  adb wait-for-device >/dev/null 2>&1
  ip_adb_prop ro.build.version.sdk >/dev/null || { echo unreadable; return; }
  sfp=$(ip_adb_prop ro.system.build.fingerprint); bfp=$(ip_adb_prop ro.build.fingerprint)
  gsid=$(adb shell getprop ro.gsid.image_running 2>/dev/null | tr -d '\r')
  lin=$(adb shell getprop ro.lineage.version 2>/dev/null | tr -d '\r')
  if [ "$gsid" != 1 ] && adb shell 'gsi_tool status 2>&1' 2>/dev/null | tr -d '\r' | grep -qiE 'running|booted'; then gt=1; fi
  ip_classify "$sfp" "$bfp" "$gsid" "$gt" "$lin"
}

# ip_require_gsi : strict guard for tools that must only run on a GSI. Exits the script on failure.
ip_require_gsi() {
  local c; c=$(ip_adb_class)
  case $c in
    flashed-gsi|dsu-gsi) echo "guard: OS=$c"; return 0;;
    stock)      echo "REFUSING: device is running STOCK firmware (system fingerprint contains rockchip/Moaan)"; exit 1;;
    unreadable) echo "REFUSING: cannot read ro.system.build.fingerprint (device offline / adbd restarting?)"; exit 1;;
    *)          echo "REFUSING: no ro.lineage.version and system fingerprint is neither stock (Moaan) nor a recognised GSI (OS=$c)"; exit 1;;
  esac
}

# ip_root_or_die : `adb root` (may be disabled by a developer setting), then verify uid 0 with retries.
ip_root_or_die() {
  local i=0 u
  adb root >/dev/null 2>&1; adb wait-for-device >/dev/null 2>&1
  while [ $i -lt 6 ]; do
    u=$(adb shell id -u 2>/dev/null | tr -d '\r')
    [ "$u" = 0 ] && return 0
    i=$((i+1)); adb wait-for-device >/dev/null 2>&1; sleep 1
  done
  echo "REFUSING: adb root unavailable (disabled by system setting or not userdebug); this tool needs root"; exit 1
}
