#!/bin/zsh
# InkPalm-KompaktOS health check. Run after every new build/boot to see which features carried over.
#
#   tools/diag/run_diag.sh [--serial SERIAL] [--out DIR] [--label NAME] [--timeout SECS]
#                          [--no-root] [--rw]
#
# READ-ONLY by default. On stock firmware it is ALWAYS read-only (no `adb root`, --rw is ignored).
# OS detection (tools/lib/inkpalm_os.sh): ro.lineage.version set => GSI (KompaktOS spoofs even the system
# fingerprint); else stock = ro.system.build.fingerprint contains rockchip/Moaan;
# anything else that looks like a GSI is flashed-gsi (or dsu-gsi if ro.gsid.image_running=1 / gsi_tool
# says running). ro.product.name / ro.build.fingerprint are NOT used (phh spoofs them to vendor values).
# `adb root` is OPTIONAL and attempted only on a GSI without --no-root; if it is disabled (developer
# setting) the run continues unrooted. --rw additionally enables idempotent write-back tests
# (e.g. `setprop sys.eink.mode <current value>`), GSI + root only.
# If properties cannot be read (adbd restarting) the run aborts instead of reporting false FAILs.
#
# Output: ~/InkPalm-Images/diag/<timestamp>[-label]/  (summary.txt, results.json, getprop.txt,
#         dumpsys/, logcat*.txt, getevent-lp.txt, screenshot.png, raw/ ...). Diff two runs with
#         tools/diag/compare.py A/results.json B/results.json
#
# Every check is independent and every adb call is wrapped in a perl-alarm timeout (macOS has none).

SCRIPT_DIR=${0:A:h}
. "$SCRIPT_DIR/../lib/inkpalm_os.sh"
TMO=25                 # per adb call timeout, seconds
SERIAL=""; OUT=""; LABEL=""; NO_ROOT=0; RW=0
EXPECTED_VENDOR_FP='rockchip/rk3566_eink/rk3566_eink:11/RQ2A.210505.003/wangyuhua12161814:user/release-keys'

while (( $# )); do
  case $1 in
    --serial)  SERIAL=$2; shift 2;;
    --out)     OUT=$2; shift 2;;
    --label)   LABEL=$2; shift 2;;
    --timeout) TMO=$2; shift 2;;
    --no-root) NO_ROOT=1; shift;;
    --rw)      RW=1; shift;;
    -h|--help) sed -n '2,20p' $0; exit 0;;
    *) print -u2 "unknown arg $1"; exit 2;;
  esac
done

ADB=(adb); [[ -n $SERIAL ]] && ADB+=(-s $SERIAL)
TS=$(date +%Y%m%d-%H%M%S)
[[ -z $OUT ]] && OUT=$HOME/InkPalm-Images/diag/$TS${LABEL:+-$LABEL}
mkdir -p $OUT/raw $OUT/dumpsys || { print -u2 "cannot create $OUT"; exit 2; }
RES=$OUT/results.tsv; MET=$OUT/metrics.tsv; META=$OUT/meta.tsv
: > $RES; : > $MET; : > $META; : > $OUT/summary.txt

# ---------------------------------------------------------------- helpers
adbt() { local t=$1; shift; perl -e 'alarm shift; exec @ARGV' $t "${ADB[@]}" "$@" </dev/null; }
sh_()  { adbt $TMO shell "$@" 2>&1 | tr -d '\r'; }                # device shell, bounded
cap()  { local n=$1; shift; sh_ "$@" > $OUT/raw/$n.txt; cat $OUT/raw/$n.txt; }  # run + save + echo
gp()   { awk -v k="[$1]" 'index($0,k":")==1{sub(/^[^:]*: \[/,"");sub(/\]$/,"");print;exit}' $OUT/getprop.txt; }
rec()  { # rec <id> <PASS|FAIL|WARN|SKIP> <detail>
  local d=${3//$'\t'/ }; d=${d//$'\n'/ | }; d=${d:0:380}
  print -r -- "$1"$'\t'"$2"$'\t'"$d" >> $RES
  printf '%-5s %-18s %s\n' $2 $1 ${d:0:150} | tee -a $OUT/summary.txt
}
metric() { print -r -- "$1"$'\t'"$2" >> $MET; }
meta()   { print -r -- "$1"$'\t'"$2" >> $META; }
recorded() { grep -q "^$1	" $RES; }
need_root() { (( ROOT )); }

run_check() { # run_check <id> <function>  : isolated, always records something
  local id=$1 fn=$2 n0=$(wc -l < $RES)
  $fn
  (( $(wc -l < $RES) > n0 )) || rec $id WARN "check produced no result"
}

# ---------------------------------------------------------------- connect + props
if ! adbt 10 get-state 2>/dev/null | grep -q device; then
  print -u2 "no adb device (adb get-state != device)"; exit 2
fi
# read_props: wait-for-device, then retry until a known prop (ro.build.version.sdk) is non-empty.
# Used at start and again after `adb root` (adbd restarts; shell output can be empty meanwhile).
read_props() { # read_props <label>
  local i
  for i in 1 2 3 4 5 6 7 8; do
    adbt 40 wait-for-device >/dev/null 2>&1
    sh_ getprop > $OUT/getprop.txt
    [[ -n $(gp ro.build.version.sdk) ]] && return 0
    sleep 2
  done
  print -u2 "ABORT: $1: getprop returned no ro.build.version.sdk after 8 tries (adbd restarting / device offline / unauthorized?). Not producing results (they would be false FAILs)."
  print -- "ABORT: properties unreadable ($1)" >> $OUT/summary.txt
  exit 3
}
read_props initial

# ---------------------------------------------------------------- OS detection
detect_os() {
  local gt=0
  if [[ $(gp ro.gsid.image_running) != 1 ]] && sh_ 'gsi_tool status 2>&1' | grep -qiE 'running|booted'; then gt=1; fi
  OS=$(ip_classify "$(gp ro.system.build.fingerprint)" "$(gp ro.build.fingerprint)" "$(gp ro.gsid.image_running)" $gt "$(gp ro.lineage.version)")
  [[ $OS == unreadable ]] && OS=unknown
}
detect_os
ROOT=0; ROOT_NOTE=""
if [[ $OS == (dsu-gsi|flashed-gsi) && $NO_ROOT == 0 ]]; then
  # Root is optional: it can be disabled by a developer setting ("ADB Root access is disabled ...").
  ROOT_NOTE=$(adbt 20 root 2>&1 | tr -d '\r' | head -1)
  read_props after-adb-root          # wait-for-device + verified props (aborts if unreadable)
  for _i in 1 2 3 4; do
    [[ $(sh_ id -u | tail -1) == 0 ]] && { ROOT=1; break; }
    sleep 1
  done
  (( ROOT )) || print "adb root not available (${ROOT_NOTE:-no output}); continuing unrooted"
  detect_os                           # re-run on refreshed props
fi
[[ $OS == (stock|unknown) ]] && RW=0
(( ROOT )) || RW=0

meta timestamp "$TS"; meta label "$LABEL"; meta os "$OS"; meta root "$ROOT"; meta rw "$RW"
meta fingerprint "$(gp ro.build.fingerprint)"; meta system_fingerprint "$(gp ro.system.build.fingerprint)"; meta root_note "$ROOT_NOTE"; meta vendor_fingerprint "$(gp ro.vendor.build.fingerprint)"
meta serial "${SERIAL:-$(gp ro.serialno)}"; meta build_type "$(gp ro.build.type)"
{
  print "InkPalm diag $TS  label=${LABEL:--}"
  print "OS=$OS root=$ROOT rw=$RW  system=$(gp ro.system.build.fingerprint)"
  print "results: $OUT"; print -- "-----"
} | tee -a $OUT/summary.txt
rec os_detect PASS "OS=$OS root=$ROOT rw=$RW product=$(gp ro.product.name) sysfp=$(gp ro.system.build.fingerprint) android=$(gp ro.build.version.release) sdk=$(gp ro.build.version.sdk)"

# ---------------------------------------------------------------- bulk collection
cap_all() {
  adbt 90 logcat -b all -d -v threadtime 2>&1 | tr -d '\r' > $OUT/logcat.txt
  adbt 30 logcat -b crash -d -v threadtime 2>&1 | tr -d '\r' > $OUT/logcat-crash.txt
  adbt 30 logcat -b events -d -v threadtime 2>&1 | tr -d '\r' > $OUT/logcat-events.txt
  sh_ getevent -lp > $OUT/getevent-lp.txt
  sh_ ps -A > $OUT/ps.txt
  sh_ 'service list' > $OUT/service-list.txt
  for s in battery power input display sensorservice media.audio_flinger wifi bluetooth_manager; do
    sh_ "dumpsys $s" > $OUT/dumpsys/$s.txt
  done
  sh_ 'dumpsys SurfaceFlinger' | head -400 > $OUT/dumpsys/SurfaceFlinger.txt
  sh_ 'dumpsys window displays' | head -150 > $OUT/dumpsys/window-displays.txt
  sh_ uname -a > $OUT/uname.txt
  if (( ROOT )); then
    sh_ dmesg > $OUT/dmesg.txt
    sh_ 'ls -l /data/tombstones /data/anr 2>&1' > $OUT/tombstones.txt
  else
    sh_ 'ls -l /data/tombstones 2>&1' > $OUT/tombstones.txt
  fi
  adbt 30 exec-out screencap -p > $OUT/screenshot.png 2>/dev/null
}
print "collecting (logcat, dumpsys, getevent, screenshot) ..."
cap_all

# ---------------------------------------------------------------- checks
SVC_N=$(grep -c '^\[init\.svc\.' $OUT/getprop.txt)   # 0 => init.svc props unreadable, not "services down"
chk_boot() {
  local bc=$(gp sys.boot_completed) up=$(sh_ 'cut -d" " -f1 /proc/uptime' | tail -1)
  if [[ $bc == 1 ]]; then rec boot_completed PASS "sys.boot_completed=1 uptime=${up}s"
  elif [[ -z $bc ]]; then rec boot_completed WARN "could not read sys.boot_completed uptime=${up}s"
  else rec boot_completed FAIL "sys.boot_completed='$bc' uptime=${up}s"; fi
  local ms=$(grep -a boot_progress_enable_screen $OUT/logcat-events.txt | tail -1 | sed -E 's/.*: *([0-9]+).*/\1/')
  if [[ -z $ms || $ms != <-> ]]; then
    local ns=$(gp ro.boottime.zygote); [[ $ns == <-> ]] && ms=$(( ns / 1000000 ))
  fi
  if [[ $ms == <-> ]]; then
    metric boot_ms $ms
    (( ms < 90000 )) && rec boot_time PASS "enable_screen at ${ms}ms" || rec boot_time WARN "slow boot: enable_screen at ${ms}ms"
  else
    rec boot_time SKIP "no boot_progress_enable_screen event (logcat rotated?)"
  fi
}
chk_crashloop() {
  local r=$(grep -E '^\[init\.svc\..*\]: \[restarting\]' $OUT/getprop.txt | sed -E 's/^\[init\.svc\.([^]]*)\].*/\1/' | tr '\n' ' ')
  local exits=$(grep -aE "init: .*Service '[^']+'.*(exited with status|killed by signal)" $OUT/logcat.txt \
      | sed -E "s/.*Service '([^']+)'.*/\1/" | sort | uniq -c | sort -rn | awk '$1>=3{printf "%s(x%d) ",$2,$1}')
  grep -aE "init: .*Service '[^']+'.*(exited with status|killed by signal)" $OUT/logcat.txt \
      | sed -E "s/.*Service '([^']+)'.*/\1/" | sort | uniq -c | sort -rn > $OUT/raw/service_exits.txt
  metric svc_restarting_now $(print -n $r | wc -w | tr -d ' ')
  if [[ -n $r ]]; then rec svc_crashloop FAIL "restarting now: $r"
  elif [[ -n $exits ]]; then rec svc_crashloop WARN "services exited >=3x in log: $exits"
  else rec svc_crashloop PASS "no restarting services, no repeated exits"; fi
}
chk_libs() {
  local L=$OUT/logcat.txt
  local cl=$(grep -ac 'CANNOT LINK EXECUTABLE' $L) dl=$(grep -ac 'dlopen failed' $L)
  grep -aoE 'library "[^"]+" not found' $L | sort | uniq -c | sort -rn > $OUT/missing_libs.txt
  grep -aoE 'cannot locate symbol "[^"]+"' $L | sort | uniq -c | sort -rn >> $OUT/missing_libs.txt
  local nm=$(wc -l < $OUT/missing_libs.txt | tr -d ' ')
  metric cannot_link $cl; metric dlopen_failed $dl
  if (( cl > 0 )); then rec lib_link FAIL "CANNOT LINK x$cl, dlopen failed x$dl, $nm distinct missing libs/symbols (missing_libs.txt)"
  elif (( dl > 0 )); then rec lib_link WARN "dlopen failed x$dl ($nm distinct)"
  else rec lib_link PASS "no CANNOT LINK / dlopen failures"; fi
}
chk_avc() {
  local L=$OUT/logcat.txt
  local tot=$(grep -ac 'avc: *denied' $L) enf=$(grep -a 'avc: *denied' $L | grep -ac 'permissive=0')
  grep -a 'avc: *denied' $L | sed -E 's/.*denied *\{ *([^}]*)\} .*scontext=u:r:([^:]+):.*tcontext=u:[a-z]+:([^:]+):.*tclass=([a-z_]+).*/\2 -> \3 :\4 {\1}/' \
     | sort | uniq -c | sort -rn | head -40 > $OUT/avc_summary.txt
  metric avc_total $tot; metric avc_enforced $enf
  local enfmode=$(sh_ getenforce | tail -1)
  if (( tot == 0 )); then rec avc PASS "no avc denials in logcat"
  elif [[ $enfmode == Enforcing && $enf -gt 0 ]]; then rec avc WARN "$enf enforced denials / $tot total (avc_summary.txt)"
  else rec avc WARN "$tot denials logged, selinux=$enfmode (avc_summary.txt)"; fi
}
chk_display() {
  local sf=$(gp init.svc.surfaceflinger)
  local hwc=$(grep -E '^\[init\.svc\..*(hwcomposer|composer).*\]' $OUT/getprop.txt | head -3 | sed -E 's/^\[init\.svc\.([^]]*)\]: \[(.*)\]/\1=\2/' | tr '\n' ' ')
  local hwc_run=$(grep -cE '^\[init\.svc\..*(hwcomposer|composer).*\]: \[running\]' $OUT/getprop.txt)
  if [[ $sf == running && $hwc_run -ge 1 ]]; then rec display_stack PASS "surfaceflinger=running composer: $hwc"
  elif [[ -z $sf ]] || (( ! SVC_N )); then rec display_stack WARN "could not read init.svc.surfaceflinger / composer props (sf='$sf')"
  else rec display_stack FAIL "surfaceflinger='$sf' composer: ${hwc:-none found}"; fi
  local st=$(python3 -I $SCRIPT_DIR/png_stats.py $OUT/screenshot.png 2>&1)
  local size=$(sh_ 'wm size' | tr '\n' ' ')
  case $st in
    ok*) local distinct=${${(s: :)st}[4]}
         if (( distinct <= 1 )); then rec display_screencap WARN "screencap is blank/uniform ($st) $size"
         else rec display_screencap PASS "screencap non-blank ($st) $size"; fi
         metric screencap_distinct $distinct;;
    *)   rec display_screencap WARN "screencap failed/unreadable: $st";;
  esac
}
chk_eink_props() {
  grep -E '^\[(sys|debug|ro\.vendor|persist\.vendor)\.eink|^\[persist\.sys\.mogu|^\[sys\.(hwc|gray|power)\.|^\[ro\.need\.white' $OUT/getprop.txt > $OUT/eink_props.txt
  local mode=$(gp sys.eink.mode) n=$(wc -l < $OUT/eink_props.txt | tr -d ' ')
  [[ -n $mode ]] && rec eink_props PASS "sys.eink.mode=$mode ($n eink/mogu props, ro.vendor.eink=$(gp ro.vendor.eink))" \
                 || rec eink_props WARN "could not read sys.eink.mode ($n related props; unset or unreadable)"
  [[ -n $mode ]] && metric eink_mode $mode
}
chk_eink_service() {
  local ebc=$(sh_ 'ls -l /dev/ebc 2>&1' | tail -1)
  local svc=$(sh_ 'service check eink' | tail -1)
  local pkg=$(sh_ 'pm list packages 2>/dev/null | grep -i eink' | tr '\n' ' ')
  if [[ $svc == *found* && $svc != *"not found"* ]]; then rec eink_service PASS "binder 'eink': found; pkgs: ${pkg:-none}; $ebc"
  elif [[ $OS == *gsi && $(gp init.svc.inkpalm_eink_bridge) == running ]]; then
    rec eink_service PASS "no binder 'eink' (expected on GSI); InkPalm bridge running; pkgs: ${pkg:-none}; $ebc"
  else rec eink_service WARN "binder 'eink' absent (GSI einkservice not installed yet?); pkgs: ${pkg:-none}; $ebc"; fi
  if (( RW )); then
    local cur=$(gp sys.eink.mode); sh_ "setprop sys.eink.mode $cur" >/dev/null
    local now=$(sh_ 'getprop sys.eink.mode' | tail -1)
    [[ $now == $cur ]] && rec eink_write PASS "idempotent setprop sys.eink.mode=$cur accepted" \
                       || rec eink_write FAIL "setprop sys.eink.mode $cur -> read back '$now'"
  else
    rec eink_write SKIP "write test disabled (read-only run; --rw on GSI+root only; on stock never)"
  fi
}
chk_touch() {
  local blk=$(perl -0777 -ne 'print grep {/fts_ts/} split /(?=^add device)/m' $OUT/getevent-lp.txt)
  if [[ -z $blk ]]; then rec touch_device FAIL "fts_ts not in getevent -lp"; rec touch_idc SKIP "no fts_ts"; return; fi
  local node=$(print -r -- "$blk" | head -1 | sed -E 's/.*: //')
  local x=$(print -r -- "$blk" | grep -a 'ABS_MT_POSITION_X' | head -1 | sed -E 's/.*min *([-0-9]+), *max *([-0-9]+).*/\1..\2/')
  local y=$(print -r -- "$blk" | grep -a 'ABS_MT_POSITION_Y' | head -1 | sed -E 's/.*min *([-0-9]+), *max *([-0-9]+).*/\1..\2/')
  rec touch_device PASS "fts_ts at $node raw X $x Y $y"
  metric touch_x_max ${x#*..}; metric touch_y_max ${y#*..}
  perl -ne 'if(/^\s+\d+: fts_ts/){$p=70} if($p>0){print;$p--}' $OUT/dumpsys/input.txt > $OUT/raw/touch_dumpsys_input.txt
  local idc=$(grep -aiE 'ConfigurationFile|Configuration file|IdcFile' $OUT/raw/touch_dumpsys_input.txt | head -1 | sed -E 's/^ +//')
  local surf=$(grep -aE 'SurfaceWidth|SurfaceHeight|Orientation' $OUT/raw/touch_dumpsys_input.txt | tr -s ' ' | tr '\n' ' ' | cut -c1-160)
  local dispwh=$(sh_ 'wm size' | grep -o '[0-9]*x[0-9]*' | tail -1)
  local hint="" idcv=${${idc#*:}// /}
  local xm=${x#*..} ym=${y#*..}
  if [[ $xm == <-> && $ym == <-> && $xm -gt $ym && ${dispwh%x*} -lt ${dispwh#*x} ]] 2>/dev/null; then
    hint=" NOTE raw axes are landscape ($xm x $ym) vs portrait display $dispwh: needs IDC/rotation, verify taps"
  fi
  if [[ ! -s $OUT/raw/touch_dumpsys_input.txt ]]; then rec touch_idc WARN "fts_ts not in dumpsys input (InputReader has not enabled it)$hint"
  elif [[ -n $idcv && $idcv != (none|\<none\>|null) ]]; then rec touch_idc PASS "$idc | $surf$hint"
  else rec touch_idc WARN "no IDC applied (ConfigurationFile empty) | $surf$hint"; fi
}
chk_keys() {
  local g=$(grep -ac 'gpio-keys' $OUT/getevent-lp.txt) p=$(grep -aic 'pwrkey' $OUT/getevent-lp.txt)
  local keys=$(perl -0777 -ne 'for (grep {/gpio-keys/} split /(?=^add device)/m){print join(" ", /(KEY_[A-Z0-9_]+)/g)}' $OUT/getevent-lp.txt | cut -c1-120)
  if (( g && p )); then rec keys PASS "gpio-keys ($keys) + rk805 pwrkey present"
  else rec keys FAIL "gpio-keys=$g pwrkey=$p"; fi
}
chk_wifi() {
  local hal=$(grep -E '^\[init\.svc\..*wifi.*\]' $OUT/getprop.txt | sed -E 's/^\[init\.svc\.([^]]*)\]: \[(.*)\]/\1=\2/' | tr '\n' ' ')
  local st=$(sh_ 'cmd wifi status' | head -3 | tr '\n' ' ')
  local iface=$(sh_ 'f=/sys/class/net/wlan0/operstate; [ -e $f ] && echo "wlan0 $(cat $f 2>&1)" || echo "no wlan0"' | head -1 | cut -c1-60)
  local scans=$(sh_ 'cmd wifi list-scan-results' | grep -cE '^ *([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}' )
  local conn=$(grep -a '^mWifiInfo SSID' $OUT/dumpsys/wifi.txt | grep -a 'Supplicant state: COMPLETED' | head -1 | sed -E 's/^mWifiInfo SSID: ("[^"]*").*RSSI: ([-0-9]+).*/\1 rssi=\2/')
  metric wifi_scan_results $scans
  if [[ -z $hal ]] && (( ! SVC_N )); then rec wifi WARN "could not read init.svc.* props"
  elif [[ $hal != *running* ]]; then rec wifi FAIL "no wifi HAL running (${hal:-none}); $iface"
  elif [[ $st == *"Wifi is enabled"* ]]; then
    if [[ -n $conn ]]; then rec wifi PASS "HAL ok, enabled, connected $conn, $scans scan results; $iface"; return; fi
    (( scans > 0 )) && rec wifi PASS "HAL ok, enabled, $scans scan results; $iface" || rec wifi WARN "HAL ok, enabled but 0 scan results; $iface"
  else rec wifi WARN "HAL ok ($hal) but status: ${st:-n/a}; $iface"; fi
}
chk_bt() {
  local hal=$(grep -E '^\[init\.svc\..*bluetooth.*\]' $OUT/getprop.txt | sed -E 's/^\[init\.svc\.([^]]*)\]: \[(.*)\]/\1=\2/' | tr '\n' ' ')
  local en=$(grep -aE '^ *enabled: |mEnable|state: ' $OUT/dumpsys/bluetooth_manager.txt | head -2 | tr -s ' ' | tr '\n' ' ')
  if [[ $hal == *running* ]]; then rec bluetooth PASS "HAL running ($hal) $en"
  elif [[ -z $hal ]] && (( ! SVC_N )); then rec bluetooth WARN "could not read init.svc.* props"
  else rec bluetooth FAIL "no bluetooth HAL running (${hal:-none}) $en"; fi
}
chk_battery() {
  local B=$OUT/dumpsys/battery.txt
  local lvl=$(grep -a 'level:' $B | head -1 | tr -dc 0-9) present=$(grep -a 'present:' $B | head -1 | awk '{print $2}') \
        bstat=$(grep -a ' status:' $B | head -1 | awk '{print $2}') temp=$(grep -a 'temperature:' $B | head -1 | tr -dc 0-9)
  metric battery_level ${lvl:-na}
  if [[ -n $lvl && $present == true ]]; then rec battery PASS "level=$lvl status=$bstat temp=$temp present=true"
  else rec battery FAIL "dumpsys battery unusable (level='$lvl' present='$present')"; fi
}
chk_light() {
  local hal=$(grep -E '^\[init\.svc\..*light.*\]' $OUT/getprop.txt | sed -E 's/^\[init\.svc\.([^]]*)\]: \[(.*)\]/\1=\2/' | tr '\n' ' ')
  local nodes=$(cap light_nodes 'for f in /sys/class/backlight/*/brightness /sys/class/leds/*/brightness; do [ -e $f ] && echo "$f=$(cat $f 2>&1)"; done')
  local ok=$(print -r -- "$nodes" | grep -cE '=[0-9]+$')
  local sys=$(sh_ 'settings get system screen_brightness' | tail -1)
  if (( ok )); then rec light PASS "lights HAL: ${hal:-none}; $ok readable nodes; settings brightness=$sys"
  elif [[ $hal == *running* ]]; then rec light WARN "lights HAL running but no readable sysfs nodes (selinux/none); brightness=$sys"
  else rec light WARN "no lights HAL and no readable brightness nodes; brightness=$sys"; fi
}
chk_sensors() {
  local S=$OUT/dumpsys/sensorservice.txt
  local n=$(grep -acE '^0x[0-9a-f]+\)' $S)
  local acc=$(grep -aic 'accel' $S) lux=$(grep -aic 'light' $S) prox=$(grep -aic 'proximity' $S)
  grep -aE '^0x[0-9a-f]+\)' $S | cut -c1-110 > $OUT/raw/sensors_list.txt
  metric sensor_count $n
  if (( n > 0 )); then rec sensors PASS "$n sensors (accel=$acc light=$lux prox=$prox)"
  else rec sensors FAIL "no sensors in dumpsys sensorservice (sensors HAL down?)"; fi
}
chk_audio() {
  local as=$(gp init.svc.audioserver); local hal=$(grep -E '^\[init\.svc\..*audio.*\]' $OUT/getprop.txt | sed -E 's/^\[init\.svc\.([^]]*)\]: \[(.*)\]/\1=\2/' | tr '\n' ' ')
  local A=$OUT/dumpsys/media.audio_flinger.txt
  local thr=$(grep -aciE 'output thread|Output devices|Standby: ' $A)
  local dev=$(grep -aE 'Output devices|Devices:' $A | head -3 | tr -s ' ' | tr '\n' ' ')
  if [[ $as == running && $thr -gt 0 ]]; then rec audio PASS "audioserver running, flinger active ($dev) hal: $hal"
  elif [[ $as == running ]]; then rec audio WARN "audioserver running but no output threads in dump; hal: $hal"
  elif [[ -z $as ]]; then rec audio WARN "could not read init.svc.audioserver (hal: ${hal:-none})"
  else rec audio FAIL "audioserver='$as' hal: ${hal:-none}"; fi
}
chk_power() {
  local P=$OUT/dumpsys/power.txt
  local wake=$(grep -a 'mWakefulness=' $P | head -1 | sed -E 's/.*mWakefulness=//')
  local dp=$(grep -a 'Display Power: state=' $P | head -1 | sed -E 's/.*state=//')
  [[ -n $wake ]] && rec power_state PASS "wakefulness=$wake display=$dp" || rec power_state FAIL "no mWakefulness in dumpsys power"
  local ss=$(cap suspend_stats 'grep -r . /sys/power/suspend_stats/ 2>&1; cat /sys/power/state 2>&1' | tr '\n' ' ')
  local ok=$(sh_ 'cat /sys/power/suspend_stats/success 2>/dev/null' | tail -1) fail=$(sh_ 'cat /sys/power/suspend_stats/fail 2>/dev/null' | tail -1)
  if (( ROOT )); then cap wakeup_sources 'cat /sys/kernel/debug/wakeup_sources 2>&1 || cat /d/wakeup_sources 2>&1' | head -40 > $OUT/raw/wakeup_sources_head.txt; fi
  if [[ $ok == <-> ]]; then
    metric suspend_success $ok; metric suspend_fail ${fail:-0}
    (( ${fail:-0} > 0 )) && rec suspend_stats WARN "suspend success=$ok fail=${fail} last_failed_dev=$(sh_ 'cat /sys/power/suspend_stats/last_failed_dev' | tail -1)" \
                         || rec suspend_stats PASS "suspend success=$ok fail=${fail:-0} (counts rise only after a real sleep)"
  else rec suspend_stats SKIP "/sys/power/suspend_stats unreadable: ${ss:0:100}"; fi
}
chk_dsu() {
  local gsid=$(gp ro.gsid.image_running)
  if [[ $gsid == 1 ]]; then
    local g=$(cap gsi_status 'gsi_tool status 2>&1' | tr '\n' ' ')
    local df=$(sh_ 'df -h /data /system /vendor 2>&1' | tail -3 | awk '{printf "%s=%s/%s ",$NF,$3,$2}')
    rec dsu_state PASS "DSU running slot=$(gp ro.boot.slot_suffix) gsi_tool: ${g:0:80}; $df"
  else rec dsu_state SKIP "not a DSU boot (ro.gsid.image_running='$gsid'), OS=$OS"; fi
}
chk_inkpalm() {  # InkPalm frontlight + InkControl / eink bridge state
  # aw99703 node prints "aw99703_brightness:N\nbrightness in reg:N": keep the first number (raw file has both)
  local fl; fl=$(cap frontlight 'for f in /proc/aw99703*/led_brightness; do [ -e $f ] && echo "$f=$(cat $f 2>&1)"; done' \
    | awk '/^\/proc\//{if(k)print k"="(n?n:v); k=$0; sub(/=.*/,"",k); v=substr($0,length(k)+2); n=""; if(match(v,/[0-9]+$/))n=substr(v,RSTART); next}
           {v=v" | "$0} END{if(k)print k"="(n?n:v)}')
  local nfl=$(print -r -- "$fl" | grep -cE '=[0-9]+$')
  local br=$(gp init.svc.inkpalm_eink_bridge) ic=$(sh_ 'pm list packages org.neoport.inkcontrol 2>/dev/null' | tr -d '\n')
  local bk=$(gp persist.sys.inkcontrol.backend)
  metric frontlight_nodes $nfl
  if (( nfl )); then rec frontlight PASS "$(print -r -- "$fl" | grep -E '=[0-9]+$' | sed 's#/proc/##;s#/led_brightness##' | tr '\n' ' ')"
  elif [[ -z $fl ]]; then rec frontlight WARN "no /proc/aw99703*/led_brightness (not an InkPalm Plus, or driver absent)"
  else rec frontlight WARN "frontlight node(s) not readable: ${fl:0:120}"; fi
  if [[ $OS == stock ]]; then rec inkcontrol_bridge SKIP "stock firmware: no InkControl / bridge expected"; return; fi
  [[ -z $br && -n $ic ]] && br="unset"
  if [[ $br == running && -n $ic ]]; then rec inkcontrol_bridge PASS "init.svc.inkpalm_eink_bridge=running; ${ic#package:} installed${bk:+; backend=$bk}"
  elif [[ -z $br && -z $ic ]]; then rec inkcontrol_bridge WARN "bridge service absent and InkControl not installed (or could not read)"
  else rec inkcontrol_bridge WARN "init.svc.inkpalm_eink_bridge='${br}' InkControl='${ic:-not installed}'"; fi
}
chk_selinux() {
  local m=$(sh_ getenforce | tail -1)
  case $m in Enforcing) rec selinux PASS "Enforcing";;
             Permissive) rec selinux WARN "Permissive (acceptable only for bring-up)";;
             *) rec selinux WARN "getenforce: $m";; esac
  meta selinux $m
}
chk_kernel() {
  local k=$(sh_ 'uname -r' | tail -1) full=$(cat $OUT/uname.txt | head -1)
  metric kernel_release "$k"
  [[ $k == 4.19.* ]] && rec kernel PASS "$full" || rec kernel WARN "unexpected kernel $full"
}
chk_vendor_fp() {
  local fp=$(gp ro.vendor.build.fingerprint)
  if [[ -z $fp ]]; then rec vendor_fp WARN "could not read ro.vendor.build.fingerprint"
  elif [[ $fp == $EXPECTED_VENDOR_FP ]]; then rec vendor_fp PASS "$fp"
  else rec vendor_fp FAIL "vendor fingerprint changed: $fp"; fi
}
chk_tombstones() {
  local fatal=$(grep -acE 'FATAL EXCEPTION|Fatal signal' $OUT/logcat-crash.txt)
  metric crash_buffer_fatal $fatal
  local t=$(grep -aE 'tombstone_[0-9]+$' $OUT/tombstones.txt | awk '{print $NF}' | tr '\n' ' ')
  local nt=$(print -n $t | wc -w | tr -d ' ')
  if grep -aqiE 'permission denied|No such file' $OUT/tombstones.txt && (( nt == 0 )); then
    if (( fatal > 0 )); then rec crashes WARN "crash buffer: $fatal fatal entries; tombstone dir unreadable (non-root)"
    else rec crashes SKIP "tombstone dir unreadable; crash buffer has 0 fatal entries"; fi
  elif (( nt > 0 || fatal > 0 )); then rec crashes WARN "$nt tombstones ($t) crash buffer fatal=$fatal"
  else rec crashes PASS "no tombstones, crash buffer clean"; fi
  metric tombstones $nt
}
chk_sleepscreen() {
  local w=$(gp persist.sys.mogu.wallpaper) sd=$(gp persist.sys.mogu.shutdown_wallpaper) gam=$(gp persist.sys.mogu.wallpaper_gamma) rot=$(gp persist.sys.mogu.rotation)
  local files=""
  if (( ! ROOT )) && [[ $OS != stock ]]; then rec sleepscreen SKIP "/data/misc unreadable without root; wallpaper_prop='$w' gamma='$gam' rotation='$rot' shutdown='$sd'"; return; fi
  if (( ROOT )); then files=$(sh_ "ls -l /data/misc/standby*.png /data/misc/poweroff*.png /data/$w 2>&1" | grep -v 'No such' | awk '{print $NF" "$5}' | tr '\n' ' ')
  elif [[ $OS == stock && -n $w ]]; then files="(stock: files unreadable by shell)"; fi
  local d="wallpaper_prop='$w' gamma='$gam' rotation='$rot' shutdown='$sd' files: ${files:-none}"
  if [[ $OS == stock ]]; then rec sleepscreen PASS "stock image from prop: $d"
  elif [[ -n $files && $files != none ]]; then rec sleepscreen PASS "custom sleep image present: $d"
  else rec sleepscreen WARN "no custom sleep image; HWC falls back to /vendor/media/standby.png (stock Moaan art): $d"; fi
}

for c in chk_boot chk_crashloop chk_libs chk_avc chk_display chk_eink_props chk_eink_service chk_touch chk_keys \
         chk_wifi chk_bt chk_battery chk_light chk_sensors chk_audio chk_power chk_dsu chk_selinux chk_kernel \
         chk_vendor_fp chk_tombstones chk_sleepscreen chk_inkpalm; do
  run_check ${c#chk_} $c
done

# ---------------------------------------------------------------- results.json + totals
python3 -I - "$OUT" <<'PY'
import json, sys, os
out = sys.argv[1]
def tsv(name):
    rows = []
    p = os.path.join(out, name)
    for line in open(p, errors='replace'):
        line = line.rstrip('\n')
        if line: rows.append(line.split('\t'))
    return rows
props = {}
for line in open(os.path.join(out, 'getprop.txt'), errors='replace'):
    line = line.rstrip('\n')
    if line.startswith('[') and ']: [' in line:
        k, v = line[1:].split(']: [', 1)
        props[k] = v.rstrip(']')
checks = {}
for r in tsv('results.tsv'):
    checks[r[0]] = {'status': r[1], 'detail': r[2] if len(r) > 2 else ''}
metrics = {}
for r in tsv('metrics.tsv'):
    v = r[1] if len(r) > 1 else ''
    try: v = float(v) if '.' in v else int(v)
    except ValueError: pass
    metrics[r[0]] = v
meta = {r[0]: (r[1] if len(r) > 1 else '') for r in tsv('meta.tsv')}
json.dump({'schema': 1, 'meta': meta, 'checks': checks, 'metrics': metrics, 'props': props},
          open(os.path.join(out, 'results.json'), 'w'), indent=1, sort_keys=True)
PY
np=$(grep -c $'\tPASS\t' $RES); nf=$(grep -c $'\tFAIL\t' $RES); nw=$(grep -c $'\tWARN\t' $RES); ns=$(grep -c $'\tSKIP\t' $RES)
print -- "-----\nPASS $np  FAIL $nf  WARN $nw  SKIP $ns   -> $OUT" | tee -a $OUT/summary.txt
(( nf > 0 )) && exit 1
exit 0
