#!/bin/zsh
# Builds InkPalmPowerWake.apk (static framework RRO, see AndroidManifest.xml) into $1.
set -euo pipefail
cd "${0:A:h}"
BT=~/Library/Android/sdk/build-tools/36.0.0
AJ=~/Library/Android/sdk/platforms/android-36/android.jar
KS=../../../keys/inkpalm.jks
W=$(mktemp -d)
$BT/aapt2 compile --dir res -o $W/res.zip
$BT/aapt2 link -I $AJ --manifest AndroidManifest.xml --min-sdk-version 30 --target-sdk-version 36 \
  $W/res.zip -o $W/unsigned.apk
$BT/zipalign -f -P 16 4 $W/unsigned.apk $W/aligned.apk
$BT/apksigner sign --v4-signing-enabled false --ks $KS --ks-pass pass:android --out "$1" $W/aligned.apk 2>/dev/null
rm -rf $W
