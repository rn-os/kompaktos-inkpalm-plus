#!/bin/zsh
# InkPalm-KompaktOS regression test for the flashed GSI. Run after every flash / bake.
#
#   tools/regress.sh [--serial SERIAL] [--out DIR] [--timeout SECS] [--skip-power]
#   tools/regress.sh --arm-poweroff  [--serial SERIAL]     (REAL auto power-off test, interactive)
#   tools/regress.sh --after-poweroff [--serial SERIAL]    (verify it, then run the default checks)
#
# Default mode is non-destructive: it exercises the power key, the root e-ink bridge, the power-off
# screen script (neutered: no real shutdown), defaults and auto brightness, and RESTORES everything
# it touches (screen ends AWAKE, settings/props/req files back, temp files removed; an EXIT trap
# does the same after Ctrl-C or an error). GSI + `adb root` only (tools/lib/inkpalm_os.sh guard).
# One PASS/FAIL/WARN/SKIP line per check, a summary, and everything is saved to
# $REGRESS_OUT (default ./regress-results)/<timestamp>/ (summary.txt, results.tsv, raw/*).
# Exit status: 0 = no FAIL, 1 = at least one FAIL, 2 = usage / no device, 3 = guard refused.
#
# Hard-won safety rules baked in:
#  - never `pkill -f` something an adb shell command line can match: kill by PID only
#  - never wake the display while sys.power.shutdown=1 (hung the vendor composer, watchdog loop):
#    every wake below is preceded by `setprop sys.power.shutdown 0`
#  - >= 3 s per wake/sleep transition (slow e-ink); no rapid loops
#  - never touch the secure sysui_qs_tiles setting (SystemUI overrides it)

SCRIPT_DIR=${0:A:h}
LIB=$SCRIPT_DIR/lib/inkpalm_os.sh
REPO=${SCRIPT_DIR:h}
TMO=25
SETTLE=5            # seconds of quiet after each power-off-screen dry run, before the next wake
SERIAL=""; OUT=""; MODE=default; SKIP_POWER=0
APP=com.inkpalmplus
APPDIR=/data/data/$APP/files
OLDAPP=org.neoport.inkcontrol
ARM_SH=/data/local/tmp/inkpalm-arm.sh
ARM_LOG=/data/local/tmp/inkpalm-arm.log
ARM_PID=/data/local/tmp/inkpalm-arm.pid
DEVTMP=/data/local/tmp/inkpalm-regress.$$

while (( $# )); do
  case $1 in
    --serial)         SERIAL=$2; shift 2;;
    --out)            OUT=$2; shift 2;;
    --timeout)        TMO=$2; shift 2;;
    --skip-power)     SKIP_POWER=1; shift;;
    --arm-poweroff)   MODE=arm; shift;;
    --yes)            YES=1; shift;;
    --after-poweroff) MODE=after; shift;;
    --live-poweroff)  MODE=live; shift;;
    -h|--help)        sed -n '2,19p' $0; exit 0;;
    *) print -u2 "unknown arg $1"; exit 2;;
  esac
done

ADB=(adb); [[ -n $SERIAL ]] && { ADB+=(-s $SERIAL); export ANDROID_SERIAL=$SERIAL; }
TS=$(date +%Y%m%d-%H%M%S)
[[ -z $OUT ]] && OUT=${REGRESS_OUT:-./regress-results}/$TS${${MODE:#default}:+-$MODE}
mkdir -p $OUT/raw || { print -u2 "cannot create $OUT"; exit 2; }
RES=$OUT/results.tsv; : > $RES; : > $OUT/summary.txt

# ---------------------------------------------------------------- helpers
# Every adb call is wrapped in a perl alarm (macOS has no timeout(1)); </dev/null so adb can't eat stdin.
adbt() { local t=$1; shift; perl -e 'alarm shift; exec @ARGV' $t "${ADB[@]}" "$@" </dev/null; }
sh_()  { adbt $TMO shell "$1" 2>&1 | tr -d '\r'; }              # one device-shell command string, bounded
shl()  { adbt ${2:-$TMO} shell "$1" 2>&1 | tr -d '\r'; }         # same, explicit timeout: shl <cmd> <secs>
rec()  { # rec <id> <PASS|FAIL|WARN|SKIP> <detail>
  local d=${3//$'\t'/ }; d=${d//$'\n'/ | }; d=${d:0:380}
  print -r -- "$1"$'\t'"$2"$'\t'"$d" >> $RES
  printf '%-5s %-22s %s\n' $2 $1 ${d:0:170} | tee -a $OUT/summary.txt
}
log()  { print -r -- "$*" | tee -a $OUT/summary.txt; }
pause() { sleep $1; }
gprop() { sh_ "getprop $1"; }
awake() { [[ $(wakefulness) == Awake ]]; }
wakefulness() { sh_ "dumpsys power 2>/dev/null | grep 'mWakefulness='" | sed -n 's/.*mWakefulness=//p' | head -1; }
sspid() { sh_ "pidof system_server"; }
# wake_up: the ONLY way this script wakes the display. Clears the shutdown flag first, then waits
# for e-ink to settle. Falls back to KEYCODE_WAKEUP if the power key did not do it.
wake_up() {
  sh_ "setprop sys.power.shutdown 0; input keyevent KEYCODE_WAKEUP" >/dev/null
  pause 3
  awake || { sh_ "setprop sys.power.shutdown 0; input keyevent KEYCODE_WAKEUP" >/dev/null; pause 3; }
}
go_sleep() { sh_ "input keyevent KEYCODE_SLEEP" >/dev/null; pause 3; }
ensure_awake() { awake || wake_up; awake; }

# req_write <file> <content>: write as root, then give the file to the app's uid like the app would.
# (root's `>` into an existing file keeps its owner + SELinux label; chown/restorecon cover new files.)
req_write() {
  sh_ "u=\$(stat -c %u $APPDIR); printf '%s\\n' '$2' > $APPDIR/$1; chown \$u:\$u $APPDIR/$1; chmod 600 $APPDIR/$1; restorecon $APPDIR/$1" >/dev/null
}
# poll_prop <prop> <expected> <secs>: wait until getprop == expected (0.5 s steps)
poll_prop() {
  local i n=$(( $3 * 2 )) v
  for (( i=0; i<n; i++ )); do
    v=$(gprop $1); [[ $v == $2 ]] && return 0; sleep 0.5
  done
  return 1
}

# ---------------------------------------------------------------- connect, guard, root
if ! adbt 10 get-state 2>/dev/null | grep -q device; then
  print -u2 "no adb device (adb get-state != device)"; exit 2
fi
if [[ ! -r $LIB ]]; then print -u2 "missing $LIB"; exit 2; fi
# The guard functions call plain `adb` and may wait-for-device: run them bounded in a subshell.
perl -e 'alarm shift; exec @ARGV' 120 zsh -c '. "$1"; ip_require_gsi && ip_root_or_die' _ $LIB </dev/null \
  | tee -a $OUT/summary.txt
(( ${pipestatus[1]} == 0 )) || { print -u2 "guard refused (not a rooted GSI) - nothing was touched"; exit 3; }
adbt 30 wait-for-device >/dev/null 2>&1
[[ $(sh_ "id -u" | tail -1) == 0 ]] || { print -u2 "not root"; exit 3; }
# right after `adb root` restarts adbd the shell can't reach binder services yet: wait for them
for _i in 1 2 3 4 5 6 7 8 9 10; do
  sh_ "cmd overlay list 2>&1 | head -1" | grep -qv "Can't find" && sh_ "service check power" | grep -q found && break
  sleep 2
done
sleep 2
UID_APP=$(sh_ "stat -c %u $APPDIR 2>/dev/null")      # empty if InkPalm+ was never run

# ---------------------------------------------------------------- state saved for the EXIT trap
typeset -A SAVED_REQ                 # req files backed up on the device
BACKED_UP=0
PO_BASE=""                           # sys.power.shutdown value we found
CLEANED=0
cleanup() {
  (( CLEANED )) && return; CLEANED=1
  # 1. flag cleared BEFORE any wake, then the screen comes back
  sh_ "setprop sys.power.shutdown 0" >/dev/null
  if [[ $MODE != arm ]]; then
    awake || wake_up
    # 2. restore the bridge request files without triggering inotifyd 'w' (cp to a dot-name the
    #    apply script ignores, then rename into place: a rename is not a close-write)
    if (( BACKED_UP )); then
      sh_ "for f in eink.req standby.req light.req power.req vendor_poweroff.png vendor_poweroff_nopower.png; do
             if [ -e $DEVTMP/bak/\$f ]; then
               cp -p $DEVTMP/bak/\$f $APPDIR/.regress.tmp && mv -f $APPDIR/.regress.tmp $APPDIR/\$f && restorecon $APPDIR/\$f
             elif [ -e $DEVTMP/bak/\$f.absent ]; then rm -f $APPDIR/\$f; fi
           done; rm -f $APPDIR/.regress.tmp" >/dev/null
    fi
    # 3. settings / props
    [[ -n ${ORIG_BMODE-} ]] && sh_ "settings put system screen_brightness_mode $ORIG_BMODE; settings put system screen_brightness $ORIG_BRIGHT" >/dev/null
    [[ -n ${ORIG_MODE+x} ]] && sh_ "setprop sys.eink.mode '$ORIG_MODE'" >/dev/null
    [[ -n ${ORIG_GAMMA+x} ]] && sh_ "setprop sys.gray.gammalevel '$ORIG_GAMMA'" >/dev/null
    [[ -n ${ORIG_TL+x} ]] && sh_ "setprop sys.eink.one_full_mode_timeline '$ORIG_TL'" >/dev/null
    awake || wake_up
  fi
  # 4. temp files
  sh_ "rm -rf $DEVTMP /data/local/tmp/inkpalm-regress-po.sh" >/dev/null
}
trap cleanup EXIT
trap 'print -u2 "interrupted"; exit 130' INT TERM

# ================================================================ opt-in: arm the real power-off
if [[ $MODE == arm ]]; then
  [[ -n $UID_APP ]] || { print -u2 "$APPDIR missing: InkPalm+ not installed/run"; exit 2; }
  print "This will POWER OFF the phone after you unplug it and let the screen sleep."
  print "Save your work. The phone stays off until you press the power button."
  if (( ${YES:-0} )); then ans=y; print "Continue? [y/N] y (--yes)"
  else read -q "?Continue? [y/N] " ans; print; fi
  [[ $ans == y ]] || { print "aborted"; exit 1; }
  old=$(sh_ "cat $ARM_PID 2>/dev/null")
  if [[ -n $old ]] && sh_ "kill -0 $old 2>&1 && echo alive" | grep -q alive; then
    sh_ "kill $old" >/dev/null; sleep 1; print "killed previous watcher (pid $old)"
  fi
  local tmpw=${TMPDIR:-/tmp}/inkpalm-arm.$$.sh
  cat > $tmpw <<'EOS'
#!/system/bin/sh
# Armed by tools/regress.sh --arm-poweroff. Drives the REAL bridge path for auto power-off:
# when nothing is powered and the screen has not been Awake for 30 s, write power.req "off=1"
# as the app uid. Gives up (and deletes itself) after 2 h.
LOG=/data/local/tmp/inkpalm-arm.log
APPDIR=/data/data/com.inkpalmplus/files
echo $$ > /data/local/tmp/inkpalm-arm.pid
log() { echo "$(date '+%F %T') $*" >> $LOG; }
log "armed pid $$"
end=$(( $(date +%s) + 7200 )); since=0; last=""
while [ "$(date +%s)" -lt $end ]; do
    powered=$(dumpsys battery | grep -c 'powered: true')
    if dumpsys power | grep -q 'mWakefulness=Awake'; then w=awake; else w=notawake; fi
    state="powered=$powered $w"
    [ "$state" != "$last" ] && { log "state: $state"; last="$state"; }
    if [ "$powered" = 0 ] && [ $w = notawake ]; then
        [ $since = 0 ] && since=$(date +%s)
        if [ $(( $(date +%s) - since )) -ge 30 ]; then
            u=$(stat -c %u $APPDIR)
            log "conditions held 30 s: writing power.req off=1 (uid $u)"
            echo 'off=1' > $APPDIR/power.req
            chown $u:$u $APPDIR/power.req; chmod 600 $APPDIR/power.req
            sleep 5; log "power.req now: $(wc -c < $APPDIR/power.req) bytes; shutdown.requested='$(getprop sys.shutdown.requested)'"
            sleep 20; log "still running 25 s after the request (shutdown did not start?)"
            rm -f /data/local/tmp/inkpalm-arm.sh /data/local/tmp/inkpalm-arm.pid; exit 0
        fi
    else
        since=0
    fi
    sleep 2
done
log "gave up after 2 h"
rm -f /data/local/tmp/inkpalm-arm.sh /data/local/tmp/inkpalm-arm.pid
EOS
  adbt 30 push $tmpw $ARM_SH >/dev/null 2>&1; rm -f $tmpw
  sh_ "rm -f $ARM_LOG; chmod 755 $ARM_SH" >/dev/null
  # detached: new session, no controlling shell, stdio away from adb
  adbt 20 shell "setsid nohup sh $ARM_SH >/dev/null 2>&1 </dev/null &" >/dev/null 2>&1
  sleep 3
  wp=$(sh_ "cat $ARM_PID 2>/dev/null")
  if [[ -n $wp ]] && sh_ "kill -0 $wp 2>&1 && echo alive" | grep -q alive; then
    print "watcher running as pid $wp (log: adb shell cat $ARM_LOG)"
  else
    print -u2 "FAILED: watcher is not running"; sh_ "cat $ARM_LOG"; exit 1
  fi
  # survive an adb reconnect?
  adbt 10 kill-server >/dev/null 2>&1; sleep 2; adbt 30 wait-for-device >/dev/null 2>&1; adbt 20 root >/dev/null 2>&1; adbt 30 wait-for-device >/dev/null 2>&1
  if sh_ "kill -0 $wp 2>&1 && echo alive" | grep -q alive; then print "watcher survived an adb disconnect: OK"
  else print -u2 "FAILED: watcher died with the adb session"; exit 1; fi
  cat <<EOM

Next steps:
  1. UNPLUG the phone (USB and charger).
  2. Press the power button to put the screen to sleep.
  3. After ~30 s of "unpowered + not awake" the watcher requests the shutdown. You should see the
     panda power-off screen, then the phone completely off within about 70 s.
  4. Power it on, reconnect USB, and run:  tools/regress.sh --after-poweroff
(The watcher gives up and removes itself after 2 h.)
EOM
  exit 0
fi

# ================================================================ opt-in: live power-off, automated
# The bridge refuses power.req while USB/AC is powered (on purpose), so this drives the same
# shutdown as root: asleep for 30 s, then `svc power shutdown` -> init runs inkpalm-poweroff.sh
# (panda via the standby path) -> power off. Then waits for the user to power on, and runs the
# after-poweroff + default checks. Only the bridge's "unpowered" gate is not exercised here
# (bridge_poweroff_awake covers its refusal path).
if [[ $MODE == live ]]; then
  print "This will POWER OFF the phone now (USB may stay connected). Save your work."
  if (( ${YES:-0} )); then print "Continue? [y/N] y (--yes)"
  else read -q "?Continue? [y/N] " ans; print; [[ $ans == y ]] || { print "aborted"; exit 1; }; fi
  sh_ "test -f /data/misc/poweroff.png && echo y" | grep -q y \
    || print "NOTE: no /data/misc/poweroff.png: no panda expected, the shutdown itself is still tested"
  sh_ "kill \$(cat $ARM_PID 2>/dev/null) 2>/dev/null; rm -f $ARM_SH $ARM_PID $ARM_LOG" >/dev/null
  ensure_awake; pause 3; go_sleep
  awake && { go_sleep; awake && { print -u2 "FAILED: screen will not sleep"; exit 1; }; }
  print "asleep; waiting 30 s like auto power-off..."; pause 30
  t0=$(date +%s)
  # Same order as the bridge's power.req: draw the image first, then request the shutdown.
  adbt 20 shell "setsid nohup sh -c 'sh /system/phh/inkpalm/inkpalm-poweroff.sh predraw; svc power shutdown' >/dev/null 2>&1 </dev/null &" >/dev/null 2>&1
  print "shutdown requested; watch the screen (expected: the panda, then off)"
  off=0
  while (( $(date +%s) - t0 < 120 )); do
    st=$(adbt 5 get-state 2>/dev/null | tr -d '\r')
    [[ $st != device ]] && { off=$(( $(date +%s) - t0 )); break; }
    sleep 2
  done
  if (( off == 0 )); then
    print -u2 "FAIL: still on adb 120 s after the shutdown request (stuck?): wakefulness=$(wakefulness)"
    exit 1
  fi
  print "PASS: phone went offline ${off}s after the request."
  print "Now press the power button to turn it on (keep USB connected); waiting up to 20 min..."
  t1=$(date +%s); back=0
  while (( $(date +%s) - t1 < 1200 )); do
    [[ $(adbt 5 get-state 2>/dev/null | tr -d '\r') == device ]] && { back=1; break; }
    sleep 5
  done
  (( back )) || { print -u2 "phone did not come back within 20 min"; exit 1; }
  for i in {1..60}; do [[ $(gprop sys.boot_completed) == 1 ]] && break; sleep 3; done
  adbt 20 root >/dev/null 2>&1; sleep 3; adbt 30 wait-for-device >/dev/null 2>&1
  for i in {1..20}; do sh_ "cmd overlay lookup android android:bool/config_showNavigationBar" | grep -q -E 'true|false' && break; sleep 2; done
  print "back up; running the after-poweroff and default checks"
  MODE=after; LIVE=1
fi

# ================================================================ default-mode preparation
[[ -n $UID_APP ]] || log "NOTE: $APPDIR does not exist: bridge checks will SKIP"
log "results: $OUT   serial=${SERIAL:-$(adbt 10 get-serialno 2>/dev/null)}"
log "-----"

# Back up every bridge request file (+ exported vendor art) so tests can't leave anything behind.
# Only when the files dir is verifiably there: an "absent" marker makes cleanup DELETE the file.
[[ -n $UID_APP ]] && sh_ "mkdir -p $DEVTMP/bak; chmod 700 $DEVTMP
     for f in eink.req standby.req light.req power.req vendor_poweroff.png vendor_poweroff_nopower.png; do
       if [ -e $APPDIR/\$f ]; then cp -p $APPDIR/\$f $DEVTMP/bak/\$f; else : > $DEVTMP/bak/\$f.absent; fi
     done" >/dev/null && BACKED_UP=1
ORIG_SHUT=$(gprop sys.power.shutdown)
INIT_WAKE=$(wakefulness)
SS0=$(sspid)
[[ $ORIG_SHUT == 1 ]] && log "WARN: sys.power.shutdown was 1 at start; clearing before any wake"
ensure_awake || log "WARN: could not wake the screen at start (wakefulness=$(wakefulness))"
log "start: system_server pid=$SS0 initial wakefulness=$INIT_WAKE sys.power.shutdown='$ORIG_SHUT'"

# ---------------------------------------------------------------- 2. power key
chk_powerkey() {
  local lk pw tg i okw=0 oks=0 fails=""
  lk=$(sh_ "cmd overlay lookup android android:bool/config_supportLongPressPowerWhenNonInteractive" | head -1)
  pw=$(sh_ "cmd overlay list | grep -m1 org.neoport.inkpalm.overlay.powerwake")
  tg=$(sh_ "content query --uri content://lineagesettings/system/torch_long_press_power_gesture" | sed -n 's/.*value=//p' | head -1)
  [[ $lk == true ]] && rec power_overlay PASS "config_supportLongPressPowerWhenNonInteractive=true" \
                    || rec power_overlay FAIL "config_supportLongPressPowerWhenNonInteractive='$lk' (want true)"
  [[ $pw == "[x]"* ]] && rec power_wake_overlay PASS "$pw" || rec power_wake_overlay FAIL "powerwake overlay not enabled: '${pw:-absent}'"
  [[ $tg == 0 ]] && rec power_torch_gesture PASS "torch_long_press_power_gesture=0" \
                 || rec power_torch_gesture FAIL "torch_long_press_power_gesture='${tg:-unset}' (want 0, else it could mask the result)"
  if (( SKIP_POWER )); then rec power_key_wake SKIP "--skip-power"; rec power_key_sleep SKIP "--skip-power"; return; fi
  ensure_awake
  for i in 1 2 3 4 5; do                    # SLEEP, wait, POWER press => must be Awake
    sh_ "setprop sys.power.shutdown 0; input keyevent 223" >/dev/null; pause 3
    sh_ "setprop sys.power.shutdown 0; input keyevent 26" >/dev/null; pause 3
    if awake; then okw=$((okw+1)); else fails+=" wake#$i=$(wakefulness)"; ensure_awake; fi
  done
  (( okw == 5 )) && rec power_key_wake PASS "5/5 sleep(223)->power(26) -> Awake" \
                 || rec power_key_wake FAIL "$okw/5 woke with the power key;$fails"
  fails=""
  for i in 1 2 3; do                        # POWER press while Awake => not Awake
    ensure_awake
    sh_ "input keyevent 26" >/dev/null; pause 3
    if ! awake; then oks=$((oks+1)); else fails+=" sleep#$i still Awake"; fi
    sh_ "setprop sys.power.shutdown 0; input keyevent 26" >/dev/null; pause 3
    awake || { fails+=" (no wake after #$i, used WAKEUP)"; wake_up; }
  done
  (( oks == 3 )) && rec power_key_sleep PASS "3/3 power press while Awake -> asleep" \
                 || rec power_key_sleep FAIL "$oks/3 slept;$fails"
  ensure_awake
}

# ---------------------------------------------------------------- 3. overlay config order
chk_overlay_order() {
  local cfg=/system/product/overlay/config/config.xml txt
  txt=$(sh_ "cat $cfg 2>&1")
  print -r -- $txt > $OUT/raw/overlay-config.xml
  if [[ $txt != *"<overlay"* ]]; then rec overlay_order FAIL "cannot read $cfg: ${txt:0:80}"; return; fi
  local r
  r=$(print -r -- $txt | awk '
    /<overlay /{ if ($0 ~ /mutable="false"/) { imm++; if (seenmut) bad=1 } else if ($0 ~ /mutable="true"/) { seenmut=1; mut++ } }
    END{ printf "%d immutable, %d mutable, %s", imm, mut, bad ? "BAD" : "ok" }')
  [[ $r == *ok ]] && rec overlay_order PASS "immutable entries first ($r)" || rec overlay_order FAIL "mutable entry before an immutable one ($r): zygote would refuse the file"
}

# ---------------------------------------------------------------- 4. traced
chk_traced() {
  local s p
  s=$(gprop init.svc.traced); p=$(gprop traced.relay_producer_port)
  [[ $s == running && -z $p ]] && rec traced PASS "init.svc.traced=running relay_producer_port empty" \
                              || rec traced FAIL "init.svc.traced='$s' relay_producer_port='$p'"
}

# ---------------------------------------------------------------- 5. bridge
chk_bridge() {
  local svc cmds a
  svc=$(gprop init.svc.inkpalm_eink_bridge)
  [[ $svc == running ]] && rec bridge_service PASS "init.svc.inkpalm_eink_bridge=running" || rec bridge_service FAIL "init.svc.inkpalm_eink_bridge='$svc'"
  cmds=$(sh_ "ps -A -o ARGS | grep '^inotifyd' ")
  print -r -- $cmds > $OUT/raw/inotifyd.txt
  for a in $OLDAPP $APP; do
    if [[ $cmds == *"/data/data/$a/files"* ]]; then rec bridge_watch_$a PASS "inotifyd watches /data/data/$a/files"
    elif ! sh_ "test -d /data/data/$a/files && echo y" | grep -q y; then rec bridge_watch_$a SKIP "$a not installed (no files dir)"
    else rec bridge_watch_$a FAIL "files dir exists but no inotifyd watch for $a"; fi
  done
  if [[ -z $UID_APP ]]; then
    for a in eink_mode eink_full gamma_reject export_png poweroff_awake; do rec bridge_$a SKIP "$APP absent"; done; return
  fi

  # --- eink.req sys.eink.mode
  local old new
  old=$(gprop sys.eink.mode); ORIG_MODE=$old
  [[ $old == 12 ]] && new=14 || new=12
  ensure_awake
  req_write eink.req "sys.eink.mode=$new"
  if poll_prop sys.eink.mode $new 2; then rec bridge_eink_mode PASS "sys.eink.mode $old -> $new within 2 s"
  else rec bridge_eink_mode FAIL "sys.eink.mode stayed '$(gprop sys.eink.mode)' after eink.req sys.eink.mode=$new (wanted $new)"; fi
  sh_ "setprop sys.eink.mode '$old'" >/dev/null; pause 1

  # --- eink.full=1 bumps the timeline
  local t0 t1 want
  t0=$(gprop sys.eink.one_full_mode_timeline); ORIG_TL=$t0
  [[ $t0 == <-> ]] && want=$(( (t0 + 1) % 1000000000 )) || want=1
  req_write eink.req "eink.full=1"
  if poll_prop sys.eink.one_full_mode_timeline $want 2; then rec bridge_eink_full PASS "one_full_mode_timeline '$t0' -> $want"
  else rec bridge_eink_full FAIL "timeline '$t0' -> '$(gprop sys.eink.one_full_mode_timeline)' (wanted $want)"; fi
  sh_ "setprop sys.eink.one_full_mode_timeline '$t0'" >/dev/null

  # --- out-of-range value is rejected
  local g0 g1
  g0=$(gprop sys.gray.gammalevel); ORIG_GAMMA=$g0
  req_write eink.req "sys.gray.gammalevel=99"; pause 2
  g1=$(gprop sys.gray.gammalevel)
  [[ $g1 != 99 ]] && rec bridge_gamma_reject PASS "gammalevel=99 rejected (value stays '$g1')" || rec bridge_gamma_reject FAIL "gammalevel=99 was accepted"
  sh_ "setprop sys.gray.gammalevel '$g0'" >/dev/null

  # --- standby.req export=1 recreates the vendor art, app-owned 0600
  sh_ "rm -f $APPDIR/vendor_poweroff.png" >/dev/null
  req_write standby.req "export=1"
  local i st=""
  for i in 1 2 3 4 5 6; do
    st=$(sh_ "stat -c '%u %a %s' $APPDIR/vendor_poweroff.png 2>/dev/null"); [[ -n $st ]] && break; sleep 0.5
  done
  if [[ $st == "$UID_APP 600 "* && ${st##* } -gt 0 ]]; then rec bridge_export_png PASS "vendor_poweroff.png uid=$UID_APP mode 0600 ${st##* } bytes"
  elif [[ -z $st ]]; then rec bridge_export_png FAIL "standby.req export=1 produced no vendor_poweroff.png (does /vendor/media/poweroff.png exist?)"
  else rec bridge_export_png FAIL "vendor_poweroff.png has 'uid mode size' = '$st' (want $UID_APP 600 >0)"; fi

  # --- power.req off=1 while Awake must NOT shut down
  ensure_awake
  local ss=$(sspid) up0 up1 left
  req_write power.req "off=1"      # written right after the awake check: bridge decides within ~1 s
  pause 4
  up1=$(shl "uptime -s; getprop sys.shutdown.requested; wc -c < $APPDIR/power.req" 15)
  left=$(sh_ "wc -c < $APPDIR/power.req"); left=${left//[ ]/}
  if [[ -z $up1 ]]; then rec bridge_poweroff_awake FAIL "device stopped answering adb after power.req off=1"
  elif [[ -n $(gprop sys.shutdown.requested) ]]; then rec bridge_poweroff_awake FAIL "sys.shutdown.requested='$(gprop sys.shutdown.requested)': a shutdown started while Awake"
  elif [[ $(sspid) != $ss ]]; then rec bridge_poweroff_awake FAIL "system_server pid changed $ss -> $(sspid)"
  elif [[ $left == 0 ]]; then rec bridge_poweroff_awake PASS "request consumed (power.req emptied), no shutdown, device still answers"
  else rec bridge_poweroff_awake WARN "no shutdown, but power.req not emptied (${left} bytes): did the bridge run?"; fi
  ensure_awake
}

# ---------------------------------------------------------------- 6. e-ink
chk_eink() {
  local fc rt buf old
  fc=$(gprop persist.vendor.fullmode_cnt); rt=$(gprop persist.sys.mogu.refresh_type)
  [[ $fc == 40 ]] && rec eink_fullmode_cnt PASS "persist.vendor.fullmode_cnt=40" || rec eink_fullmode_cnt FAIL "persist.vendor.fullmode_cnt='$fc' (want 40)"
  [[ -z $rt || $rt == 0 ]] && rec eink_refresh_type PASS "persist.sys.mogu.refresh_type='${rt:-<unset>}'" \
                           || rec eink_refresh_type FAIL "persist.sys.mogu.refresh_type='$rt' (HWC ignores sys.eink.mode unless 0/unset)"
  ensure_awake
  old=$(gprop sys.eink.mode); [[ -z ${ORIG_MODE+x} ]] && ORIG_MODE=$old
  sh_ "setprop sys.eink.mode 12" >/dev/null
  sh_ "cmd statusbar expand-notifications" >/dev/null; pause 3
  sh_ "cmd statusbar collapse" >/dev/null; pause 3
  buf=$(sh_ "cat /sys/devices/platform/ebc-dev/ebc_buf_state")
  print -r -- $buf > $OUT/raw/ebc_buf_state.txt
  local ms; ms=$(print -r -- $buf | sed -n 's/.*[ ,]m = \([0-9]*\).*/\1/p' | sort -u | tr '\n' ' ')
  if [[ -z $ms ]]; then rec eink_buf_mode FAIL "ebc_buf_state unreadable/empty"
  elif [[ " $ms" == *" 12 "* || " $ms" == *" 16 "* ]]; then rec eink_buf_mode PASS "ebc_buf_state m = ${ms}(12 or 16 present) after sys.eink.mode=12 + redraw"
  else rec eink_buf_mode FAIL "ebc_buf_state m = ${ms}after sys.eink.mode=12 + redraw (want 12 or 16)"; fi
  sh_ "setprop sys.eink.mode '$old'" >/dev/null
  ensure_awake
}

# ---------------------------------------------------------------- 7. power-off screen dry run
chk_poweroff_dry() {
  if (( SKIP_POWER )); then rec poweroff_dryrun SKIP "--skip-power"; return; fi
  if ! sh_ "test -f /data/misc/poweroff.png && echo y" | grep -q y; then rec poweroff_dryrun SKIP "/data/misc/poweroff.png absent (no custom image installed)"; return; fi
  local src=/system/phh/inkpalm/inkpalm-poweroff.sh orig=$OUT/raw/poweroff-orig.sh mod=$OUT/raw/poweroff-dry.sh
  sh_ "cat $src" > $orig
  [[ -s $orig ]] || { rec poweroff_dryrun FAIL "cannot read $src"; return; }
  # `predraw` = the auto power-off's own draw step: wake, LEDs off, sleep via the standby path, exit.
  # It never requests a shutdown or reaches the safety net (that is only on the init path).
  if ! grep -q 'PRE=1' $orig || ! grep -q '\[ \$PRE = 1 \] && { sleep 2; log "predraw done"; exit 0; }' $orig \
     || grep -q 'setprop sys.power.shutdown 1' $orig; then
    rec poweroff_dryrun FAIL "$src has no safe predraw mode (script changed?): refusing to run it"; return
  fi
  local n ss ss2 st sf bad=""
  ss=$(sspid)
  for n in 1 2 3; do
    ensure_awake
    pause 3
    go_sleep; pause 3                                  # start the run asleep, like auto power-off does
    sh_ "setprop sys.power.shutdown 0" >/dev/null
    sh_ "logcat -c; setprop sys.hwc.log 1" >/dev/null
    shl "sh $src predraw" 70 > $OUT/raw/poweroff-run$n.txt
    # Proof of the draw: the HWC logs the standby image it used (user_def_img = ...).
    drew=$(sh_ "logcat -d | grep -c 'user_def_img = /data/misc/poweroff'" | tail -1)
    sh_ "setprop sys.hwc.log 0" >/dev/null
    [[ ${drew:-0} -ge 1 ]] || bad+=" run${n}:HWC-did-not-draw-poweroff.png"
    pause 3
    st=$(wakefulness); ss2=$(sspid)
    sf=$(shl "timeout 8 dumpsys SurfaceFlinger --display-id 2>&1 | head -1" 20)
    [[ $st == Awake ]] && bad+=" run${n}:still-Awake"
    [[ $ss2 != $ss ]] && bad+=" run${n}:system_server $ss->$ss2"
    [[ $sf == *[Dd]isplay* ]] || bad+=" run${n}:SurfaceFlinger-silent('${sf:0:40}')"
    # The real health signal: the kernel's ebc_thread exits on an EPD_POWER_OFF frame, after
    # which any wake eventually hangs the composer (the HWC's sys.power.shutdown path).
    et=$(sh_ "ps -A | grep -c '\[ebc_thread\]'" | tail -1)
    [[ $et == 0 ]] && bad+=" run${n}:ebc_thread-gone"
    wp=$(gprop persist.sys.mogu.wallpaper)            # kept set on purpose until boot: clear it
    [[ $wp == /data/misc/poweroff* ]] || bad+=" run${n}:wallpaper-prop-not-set('$wp')"
    sh_ "setprop persist.sys.mogu.wallpaper ''" >/dev/null
    log "      dry run $n: wakefulness=$st system_server=$ss2 sf='${sf:0:60}' ebc_thread=$et wallpaper='$wp'"
    sh_ "setprop sys.power.shutdown 0" >/dev/null     # BEFORE any further wake
    pause $SETTLE                                      # let the e-ink settle before the next wake
    [[ -n $bad ]] && break
    awake && continue
  done
  wake_up
  [[ -z $bad ]] && rec poweroff_dryrun PASS "3/3 runs: not Awake after, same system_server ($ss), SurfaceFlinger answered, ebc_thread alive, HWC drew poweroff.png" \
                || rec poweroff_dryrun FAIL "$bad"
}

# ---------------------------------------------------------------- 8. defaults + cleanup
chk_defaults() {
  local d pk missing="" bad="" p
  d=$(sh_ "wm density")
  [[ $d == *"Override density: 312"* ]] && rec defaults_density PASS "Override density: 312" || rec defaults_density FAIL "wm density: ${d//$'\n'/ | }"
  d=$(sh_ "ls /data/misc/inkpalm")
  [[ $d == *defaults-v1* && $d == *defaults-v2* && $d == *defaults-v3* ]] && rec defaults_markers PASS "defaults-v1 v2 v3 present" \
                                                                         || rec defaults_markers FAIL "markers: ${d//$'\n'/ }"
  # package list: parsed from the v3 block of the repo's inkpalm-defaults.sh (source of truth)
  local pkgs; pkgs=(${(f)"$(awk '/defaults-v3 \]/{f=1} f&&/for p in/{g=1} g{e=($0 ~ /; do/); gsub(/for p in|; do.*|\\/,""); print; if(e) exit}' $REPO/gsi/vendor-fix/inkpalm-defaults.sh | tr -s ' \t' '\n\n' | grep -v '^$')"})
  if (( ${#pkgs} < 10 )); then rec defaults_removed WARN "could not parse v3 package list from $REPO/gsi/vendor-fix/inkpalm-defaults.sh (${#pkgs})"
  else
    pk=$(sh_ "pm list packages")
    print -r -- $pk > $OUT/raw/pm-list-packages.txt
    for p in $pkgs; do print -r -- $pk | grep -qx "package:$p" && bad+=" $p"; done
    [[ -z $bad ]] && rec defaults_removed PASS "${#pkgs} v3 packages absent from pm list packages" || rec defaults_removed FAIL "still installed:$bad"
  fi
  local dis; dis=$(sh_ "dumpsys package com.kompakt.service" | awk '/^ *User 0:/{u=1} /disabledComponents:/{d=1;next} d&&/^ *[A-Za-z]/&&!/\./{d=0} d&&/KompaktActivity/{print "yes"}' | head -1)
  [[ -z $dis ]] && dis=$(sh_ "dumpsys package com.kompakt.service" | grep -A8 disabledComponents: | grep -c 'com.kompakt.service.KompaktActivity' | sed 's/^0$//;s/^[1-9].*$/yes/')
  [[ $dis == yes ]] && rec defaults_kompakt_activity PASS "com.kompakt.service.KompaktActivity disabled" || rec defaults_kompakt_activity FAIL "KompaktActivity not in disabledComponents"
  local kp; kp=$(sh_ "pidof com.kompakt.service")
  [[ -n $kp ]] && rec defaults_kompakt_service PASS "com.kompakt.service running (pid $kp)" || rec defaults_kompakt_service FAIL "com.kompakt.service not running"
  local k v out=""
  bad=""
  for k in window_animation_scale transition_animation_scale animator_duration_scale; do
    v=$(sh_ "settings get global $k"); out+="$k=$v "
    [[ $v == 0 || $v == 0.0 ]] || bad+=" $k"
  done
  [[ -z $bad ]] && rec defaults_animations PASS "$out" || rec defaults_animations FAIL "nonzero:$bad ($out)"
}

# ---------------------------------------------------------------- 9. auto brightness
chk_autobright() {
  ensure_awake || { rec autobright SKIP "screen would not wake"; return; }
  ORIG_BMODE=$(sh_ "settings get system screen_brightness_mode"); ORIG_BRIGHT=$(sh_ "settings get system screen_brightness")
  if [[ $ORIG_BMODE != <-> || $ORIG_BRIGHT != <-> ]]; then unset ORIG_BMODE ORIG_BRIGHT; rec autobright WARN "cannot read brightness settings"; return; fi
  local i hit="" pre
  pre=$(sh_ "dumpsys sensorservice" | grep -A1 'com.inkpalmplus' | grep -c 'Light sensor')
  sh_ "settings put system screen_brightness_mode 1" >/dev/null
  for i in 1 2 3 4 5 6; do
    sh_ "dumpsys sensorservice" > $OUT/raw/sensorservice.txt
    if grep -A1 'com.inkpalmplus' $OUT/raw/sensorservice.txt | grep -q 'Light sensor'; then hit=$i; break; fi
    sleep 0.5
  done
  [[ -n $hit ]] && rec autobright_sensor PASS "Light sensor active for com.inkpalmplus within $(( hit / 2.0 )) s of mode=1 (was active before: $pre)" \
                || rec autobright_sensor FAIL "no com.inkpalmplus Light sensor connection 3 s after screen_brightness_mode=1 (see raw/sensorservice.txt)"
  sh_ "settings put system screen_brightness_mode $ORIG_BMODE; settings put system screen_brightness $ORIG_BRIGHT" >/dev/null
  pause 2
  local m b; m=$(sh_ "settings get system screen_brightness_mode"); b=$(sh_ "settings get system screen_brightness")
  if [[ $m == $ORIG_BMODE && $b == $ORIG_BRIGHT ]]; then rec autobright_restore PASS "mode=$m brightness=$b restored"
  elif [[ $m == $ORIG_BMODE && $ORIG_BMODE == 1 ]]; then rec autobright_restore WARN "mode restored; brightness $b != $ORIG_BRIGHT (auto mode: the app/system adjusts it itself)"
  else rec autobright_restore FAIL "mode/brightness now $m/$b, were $ORIG_BMODE/$ORIG_BRIGHT"; fi
  unset ORIG_BMODE ORIG_BRIGHT
}

# ---------------------------------------------------------------- 1. boot health (start/end)
chk_boot_health() {   # chk_boot_health  (called last: needs the full run's logcat and pid comparison)
  local bc lc ss1
  bc=$(gprop sys.boot_completed)
  [[ $bc == 1 ]] && rec boot_completed PASS "sys.boot_completed=1" || rec boot_completed FAIL "sys.boot_completed='$bc'"
  adbt 90 logcat -b all -d -v threadtime 2>&1 | tr -d '\r' > $OUT/raw/logcat-all.txt
  local g z
  g=$(grep -c 'GOODBYE' $OUT/raw/logcat-all.txt); z=$(grep -ci 'zygote died' $OUT/raw/logcat-all.txt)
  if (( g == 0 && z == 0 )); then rec boot_logcat PASS "no GOODBYE / zygote died in logcat -b all ($(wc -l < $OUT/raw/logcat-all.txt) lines)"
  else rec boot_logcat FAIL "GOODBYE x$g, 'zygote died' x$z in logcat -b all (raw/logcat-all.txt)"; fi
  ss1=$(sspid)
  [[ -n $ss1 && $ss1 == $SS0 ]] && rec boot_system_server_pid PASS "system_server pid unchanged ($SS0) through the run" \
                                || rec boot_system_server_pid FAIL "system_server pid $SS0 -> '$ss1' (restarted during the run)"
}

# ================================================================ after-poweroff mode
chk_after_poweroff() {
  local logtxt br hist last start dbx wd
  logtxt=$(sh_ "cat $ARM_LOG 2>&1")
  print -r -- $logtxt > $OUT/raw/arm.log; log "--- watcher log ---"; print -r -- $logtxt | tee -a $OUT/summary.txt; log "-------------------"
  start=$(print -r -- $logtxt | head -1 | cut -c1-19)
  if (( ${LIVE:-0} )); then rec arm_log SKIP "--live-poweroff (no watcher)"
  else
  [[ $logtxt == *"writing power.req"* ]] && rec arm_log PASS "watcher fired power.req" \
     || { [[ $logtxt == *"gave up"* ]] && rec arm_log FAIL "watcher gave up (conditions never held)" || rec arm_log WARN "no firing line in $ARM_LOG (watcher missing/never fired)"; }
  fi
  br=$(gprop sys.boot.reason); hist=$(gprop persist.sys.boot.reason.history); last=$(print -r -- $hist | tail -1)
  print -r -- "sys.boot.reason=$br\npersist.sys.boot.reason.history=$hist\nlast_reason=$(gprop sys.boot.reason.last)" > $OUT/raw/boot-reason.txt
  local lr=$(gprop sys.boot.reason.last)
  if [[ $br == (reboot,|)shutdown* || $last == (reboot,|)shutdown* || $lr == (reboot,|)shutdown* ]]; then
    rec after_boot_reason PASS "sys.boot.reason='$br' last history='${last:0:60}' reason.last='$lr'"
  else rec after_boot_reason FAIL "no shutdown* reason: sys.boot.reason='$br' history last='${last:0:60}' reason.last='$lr'"; fi
  sh_ "dumpsys dropbox --print SYSTEM_LAST_KMSG | tail -n 25" > $OUT/raw/last-kmsg-tail.txt
  if [[ -s $OUT/raw/last-kmsg-tail.txt ]]; then
    rec after_last_kmsg PASS "SYSTEM_LAST_KMSG tail saved ($(wc -l < $OUT/raw/last-kmsg-tail.txt) lines): $(tail -n 1 $OUT/raw/last-kmsg-tail.txt | cut -c1-90)"
  else rec after_last_kmsg WARN "no SYSTEM_LAST_KMSG entry in dropbox"; fi
  dbx=$(sh_ "dumpsys dropbox"); print -r -- $dbx > $OUT/raw/dropbox-list.txt
  wd=$(print -r -- $dbx | grep -i watchdog | awk -v s="${start:-0000}" '{ts=$1" "$2; if (s=="" || ts>=s) print}')
  [[ -z $wd ]] && rec after_no_watchdog PASS "no watchdog dropbox entries since the watcher was armed (${start:-?})" \
               || rec after_no_watchdog FAIL "watchdog entries: $(print -r -- $wd | head -3)"
  sh_ "rm -f $ARM_SH $ARM_LOG $ARM_PID" >/dev/null
  log "arm files removed; running the default checks"
}

# ================================================================ run
if [[ $MODE == after ]]; then
  SS0=$(sspid); chk_after_poweroff; log "-----"
  SS0=$(sspid)
fi

chk_powerkey
chk_overlay_order
chk_traced
chk_bridge
chk_eink
chk_poweroff_dry
chk_defaults
chk_autobright
chk_boot_health

# ---------------------------------------------------------------- final state + summary
cleanup
final_w=$(wakefulness)
[[ $final_w == Awake ]] && rec final_awake PASS "screen Awake, sys.power.shutdown=$(gprop sys.power.shutdown), temp files removed" \
                        || rec final_awake FAIL "screen ends $final_w"
left=$(sh_ "ls -d /data/local/tmp/inkpalm-regress* 2>/dev/null")
[[ -z $left ]] || rec final_tmpfiles FAIL "temp files left: $left"
log "-----"
np=$(grep -c $'\tPASS\t' $RES); nf=$(grep -c $'\tFAIL\t' $RES); nw=$(grep -c $'\tWARN\t' $RES); ns=$(grep -c $'\tSKIP\t' $RES)
log "SUMMARY: $np PASS, $nf FAIL, $nw WARN, $ns SKIP   (results: $OUT)"
(( nf == 0 ))
