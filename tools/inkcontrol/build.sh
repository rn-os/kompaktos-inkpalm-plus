#!/bin/zsh
# Builds build/inkcontrol.apk — per-app e-ink modes, full-refresh + mode QS tiles,
# per-app colour inversion, for the Moaan InkPalm Plus (stock Android 11, no root/flash).
#   1. Compile the Java against the public SDK (hidden APIs are used via reflection/raw binder)
#   2. Dex with d8
#   3. aapt2 compile res/ + link manifest (targetSdk 30 is REQUIRED: eink_service is
#      denied by SELinux for untrusted_app_29 but allowed for untrusted_app targetSdk>=30)
#   4. Add classes.dex, align, sign with keys/inkpalm.jks (no v4 sig)
set -euo pipefail
cd "${0:A:h}"

BT=~/Library/Android/sdk/build-tools/36.0.0
AJ=~/Library/Android/sdk/platforms/android-34/android.jar
OUT=../../build/inkcontrol
APK=../../build/inkcontrol.apk
KS=../../keys/inkpalm.jks

rm -rf $OUT && mkdir -p $OUT/cls
srcs=($(find src -name '*.java'))
javac --release 11 -nowarn -cp $AJ -d $OUT/cls $srcs
java -cp $BT/lib/d8.jar com.android.tools.r8.D8 --release --min-api 30 --lib $AJ \
  --output $OUT $(find $OUT/cls -name '*.class')

$BT/aapt2 compile --dir res -o $OUT/res.zip
$BT/aapt2 link -I $AJ --manifest AndroidManifest.xml \
  --min-sdk-version 30 --target-sdk-version 30 $OUT/res.zip -o $OUT/base.apk
(cd $OUT && cp base.apk app.apk && zip -q -j app.apk classes.dex)

$BT/zipalign -f -P 16 4 $OUT/app.apk $OUT/aligned.apk
rm -f $APK.idsig
if [ -n "${PLATFORM_KEY:-}" ]; then
  # GSI build: sign with the GSI's platform key (AOSP test key: PLATFORM_KEY=<dir with
  # platform.pk8 + platform.x509.pem>) so the app runs as platform_app and may set sys.eink.*.
  APK=../../build/inkcontrol-platform.apk
  $BT/apksigner sign --v4-signing-enabled false --key $PLATFORM_KEY/platform.pk8 \
    --cert $PLATFORM_KEY/platform.x509.pem --out $APK $OUT/aligned.apk
else
  $BT/apksigner sign --v4-signing-enabled false --ks $KS --ks-pass pass:android \
    --out $APK $OUT/aligned.apk 2>/dev/null
fi
$BT/apksigner verify $APK 2>/dev/null
echo "Built $APK"
