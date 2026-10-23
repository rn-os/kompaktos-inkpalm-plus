package org.neoport.einkservice;

import android.content.Context;
import android.content.SharedPreferences;

/** Settings, kept in device-protected storage so the panel is configured before the first unlock. */
final class EinkPrefs {
    private final SharedPreferences p;

    EinkPrefs(Context c) {
        Context dp = c.isDeviceProtectedStorage() ? c : c.createDeviceProtectedStorageContext();
        p = dp.getSharedPreferences("einkservice", Context.MODE_PRIVATE);
    }

    String globalMode() {
        String v = p.getString("mode", null);
        return v != null && EinkModes.ALL.containsKey(v) ? v : EinkModes.DEFAULT;
    }
    void setGlobalMode(String v) { p.edit().putString("mode", v).apply(); }

    /** The mode for a package: its own if set, else the global one. */
    String appMode(String pkg) {
        String v = p.getString("app_mode_" + pkg, null);
        return v != null && EinkModes.ALL.containsKey(v) ? v : globalMode();
    }
    void setAppMode(String pkg, String v) {
        SharedPreferences.Editor e = p.edit();
        if (v == null) e.remove("app_mode_" + pkg); else e.putString("app_mode_" + pkg, v);
        e.apply();
    }

    boolean perApp() { return p.getBoolean("per_app", true); }
    boolean invertWanted(String pkg) { return p.getBoolean("invert_" + pkg, false); }
    void setInvert(String pkg, boolean on) {
        SharedPreferences.Editor e = p.edit();
        if (on) e.putBoolean("invert_" + pkg, true); else e.remove("invert_" + pkg);
        e.apply();
    }
    boolean invertOurs() { return p.getBoolean("invert_ours", false); }
    void setInvertOurs(boolean v) { p.edit().putBoolean("invert_ours", v).apply(); }

    /** Run a full refresh after unlock / screen on (Kompakt: UnlockRefresh). */
    boolean unlockRefresh() { return p.getBoolean("unlock_refresh", true); }

    /** "frame" = bump sys.eink.one_full_mode_timeline; "mode2" = flash Full GC16 700 ms; "overlay" = black window 480 ms. */
    String refreshStyle() { return p.getString("refresh_style", "frame"); }
    void setRefreshStyle(String v) { p.edit().putString("refresh_style", v).apply(); }

    // ---- Rockchip extras, written verbatim to the vendor props (semantics UNVERIFIED except fullmode_cnt default) ----
    /** persist.sys.mogu.refresh_type; stock SystemUI writes the per-app "refresh_mode" here, default 0. */
    String refreshType() { return p.getString("rk_refresh_type", "0"); }
    /** persist.sys.mogu.system_type; "1" for Moaan system apps, "0" otherwise. */
    String systemType() { return p.getString("rk_system_type", "0"); }
    /** persist.vendor.fullmode_cnt; stock SystemUI default "40" ("refresh frequency" slider). */
    String fullmodeCnt() { return p.getString("rk_fullmode_cnt", "40"); }
    /** persist.sys.mogu.256gray, null = untouched. */
    String gray256() { return p.getString("rk_gray256", null); }
    /** debug.sf.gamma.gamma, null = untouched (stock default derived from index 9 of 1.5..0.1 table, i.e. 0.6; UNVERIFIED). */
    String gamma() { return p.getString("rk_gamma", null); }

    /** Opt-in: start/stop the vendor "standby" service around screen off/on (see DESIGN.md, UNVERIFIED semantics). */
    boolean standbyRelay() { return p.getBoolean("standby_relay", false); }

    void putString(String k, String v) { p.edit().putString(k, v).apply(); }
    void putBool(String k, boolean v) { p.edit().putBoolean(k, v).apply(); }
}
