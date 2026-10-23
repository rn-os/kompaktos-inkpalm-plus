#!/bin/zsh
# Rebuild + reinstall InkControl and re-bind its accessibility service, keeping
# whatever other accessibility services the user already has enabled.
set -e
cd "${0:A:h}/.."
tools/inkcontrol/build.sh | tail -1
adb install -r --no-incremental build/inkcontrol.apk | tail -1
adb shell pm grant org.neoport.inkcontrol android.permission.WRITE_SECURE_SETTINGS
S="org.neoport.inkcontrol/org.neoport.inkcontrol.AppWatcherService"
cur=$(adb shell settings get secure enabled_accessibility_services | tr -d '\r')
others=$(echo "$cur" | tr ':' '\n' | grep -v -x "$S" | grep -v -x null | paste -sd: -)
adb shell settings put secure enabled_accessibility_services "${others:-null}"
sleep 2
adb shell settings put secure enabled_accessibility_services "${others:+$others:}$S"
sleep 3
echo "bound: $(adb shell dumpsys accessibility | grep -c 'InkControl per-app')"
