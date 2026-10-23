package org.neoport.einkservice;

import android.os.SystemProperties;
import android.util.Log;

/**
 * Rockchip EBC backend for the Moaan InkPalm Plus. Replaces stock EinkService.setProperty
 * (system_server -> SystemProperties.set) and the Moaan SystemUI EinkSettingsManager/Provider.
 *
 * Two write paths:
 *  - RELAY (default): set our own platform-owned prop sys.inkpalm.*; init (einkservice.rc) copies it to the real
 *    vendor prop with `setprop`. Needs only platform types in sepolicy and sidesteps the neverallow that
 *    (probably, UNVERIFIED) forbids coredomains from setting vendor_ebook_prop.
 *  - DIRECT (persist.sys.inkpalm.eink_direct=1): SystemProperties.set on the vendor prop. Needs the
 *    sepolicy rule from sepolicy/einkservice.te (direct section).
 */
final class RkEinkBackend implements EinkBackend {
    private static final String TAG = "InkPalmEink";

    // Real (vendor-read) props. Names recovered from stock framework.jar / SystemUI.apk.
    static final String P_MODE = "sys.eink.mode";
    static final String P_FULL_FRAME = "sys.eink.one_full_mode_timeline";
    static final String P_REFRESH_TYPE = "persist.sys.mogu.refresh_type";
    static final String P_SYSTEM_TYPE = "persist.sys.mogu.system_type";
    static final String P_FULLMODE_CNT = "persist.vendor.fullmode_cnt";
    static final String P_GRAY256 = "persist.sys.mogu.256gray";
    static final String P_GAMMA = "debug.sf.gamma.gamma";

    // Our relay props (einkservice.rc maps each to the one above).
    private static final String R_PREFIX = "sys.inkpalm.";
    static final String R_STANDBY = R_PREFIX + "standby";
    static final String R_DRAWPATH = R_PREFIX + "drawpath";

    private static final int FRAME_WRAP = 1_000_000;

    private int frameCounter = -1;

    @Override public String name() { return "rockchip-ebc"; }

    @Override public boolean available() {
        return new java.io.File("/dev/ebc").exists() || new java.io.File("/dev/waveform").exists();
    }

    private static boolean direct() { return SystemProperties.getInt("persist.sys.inkpalm.eink_direct", 0) == 1; }

    private boolean put(String realKey, String relayKey, String value) {
        String key = direct() ? realKey : relayKey;
        try {
            SystemProperties.set(key, value);
            return true;
        } catch (RuntimeException e) {
            // Denied by SELinux or property_service (check `adb logcat -b all | grep -E 'avc|property'`).
            Log.w(TAG, "cannot set " + key + "=" + value + ": " + e);
            return false;
        }
    }

    private static String relay(String suffix) { return R_PREFIX + suffix; }

    @Override public void applyBootDefaults(EinkPrefs prefs) {
        // Stock: EinkSettingsProvider.query writes these when an app is in front; nothing else set them.
        put(P_REFRESH_TYPE, relay("refresh_type"), prefs.refreshType());
        put(P_SYSTEM_TYPE, relay("system_type"), prefs.systemType());
        put(P_FULLMODE_CNT, relay("fullmode_cnt"), prefs.fullmodeCnt());
        if (prefs.gray256() != null) put(P_GRAY256, relay("gray256"), prefs.gray256());
        if (prefs.gamma() != null) put(P_GAMMA, relay("gamma"), prefs.gamma());
        applyMode(EinkModes.get(prefs.globalMode()), prefs);
    }

    @Override public void applyMode(EinkModes.Mode m, EinkPrefs prefs) {
        put(P_MODE, relay("eink_mode"), Integer.toString(m.rk));
        if (m.rkGamma != null) put(P_GAMMA, relay("gamma"), m.rkGamma);
    }

    /** Mirror of EinkManager.sendOneFullFrame(): bump a counter the HWC watches. */
    @Override public boolean fullRefresh() {
        if (frameCounter < 0) frameCounter = SystemProperties.getInt(R_PREFIX + "full_frame", 0);
        frameCounter = frameCounter >= FRAME_WRAP ? 1 : frameCounter + 1;
        return put(P_FULL_FRAME, relay("full_frame"), Integer.toString(frameCounter));
    }

    @Override public void onScreenState(boolean interactive, EinkPrefs prefs) {
        // Opt-in until the vendor "standby"/"einkdrawpath" services are understood (DESIGN.md section 4).
        if (!prefs.standbyRelay()) return;
        try {
            SystemProperties.set(R_STANDBY, interactive ? "0" : "1");
        } catch (RuntimeException e) {
            Log.w(TAG, "standby relay failed: " + e);
        }
    }
}
