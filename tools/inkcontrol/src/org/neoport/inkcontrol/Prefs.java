package org.neoport.inkcontrol;

import android.content.Context;
import android.content.SharedPreferences;

final class Prefs {
    static final int STOCK_DEFAULT_MODE = 7;

    private static final String FILE = "inkcontrol";
    private static final String K_DEFAULT = "default_mode";
    private static final String K_SEEDED = "seeded";
    private static final String K_WE_INVERTED = "we_inverted";

    private static final String K_FOLLOW = "follow_kompakt";
    private static final String K_PIGGYBACK = "kompakt_flash";
    private static final String K_LAST_MASTER = "kompakt_last_master";

    final SharedPreferences sp;
    private final java.io.File filesDir;

    Prefs(Context c) {
        filesDir = c.getApplicationContext().getFilesDir();
        sp = c.getApplicationContext().getSharedPreferences(FILE, Context.MODE_PRIVATE);
        seed();
    }

    /** First run: sensible suggestions; the user can change/clear them in the UI. */
    private void seed() {
        if (sp.getBoolean(K_SEEDED, false)) return;
        SharedPreferences.Editor e = sp.edit();
        String[] readers = {"com.onyx.kreader", "org.koreader.launcher", "org.koreader.launcher.fdroid",
                "org.neoport.neoreader"};
        for (String p : readers) e.putInt("mode:" + p, 8);
        String[] fast = {"com.android.chrome", "org.mozilla.firefox", "com.whatsapp",
                "org.telegram.messenger", "org.thoughtcrime.securesms", "com.android.mms",
                "com.google.android.apps.messaging"};
        for (String p : fast) e.putInt("mode:" + p, 14);
        e.putBoolean(K_SEEDED, true).apply();
    }

    int defaultMode() { return sp.getInt(K_DEFAULT, STOCK_DEFAULT_MODE); }
    void setDefaultMode(int m) { sp.edit().putInt(K_DEFAULT, m).apply(); }

    int appMode(String pkg) { return sp.getInt("mode:" + pkg, Modes.DEFAULT); }
    void setAppMode(String pkg, int m) {
        if (m == Modes.DEFAULT) sp.edit().remove("mode:" + pkg).apply();
        else sp.edit().putInt("mode:" + pkg, m).apply();
    }

    /** Use KompaktOS' per-app config when its copy is available (see KompaktSync). */
    boolean followKompakt() { return sp.getBoolean(K_FOLLOW, true); }
    void setFollowKompakt(boolean v) { sp.edit().putBoolean(K_FOLLOW, v).apply(); }

    /** Turn the black overlay KompaktService shows (QS refresh tile, long-press Home, after a
     *  mode tile) into a real Full GC16 flash. */
    boolean flashOnKompaktRefresh() { return sp.getBoolean(K_PIGGYBACK, true); }
    void setFlashOnKompaktRefresh(boolean v) { sp.edit().putBoolean(K_PIGGYBACK, v).apply(); }

    /** KompaktOS config if following and present, else null. */
    KompaktSync kompakt() { return followKompakt() ? KompaktSync.get(filesDir) : null; }

    boolean appInvert(String pkg) { return sp.getBoolean("invert:" + pkg, false); }
    void setAppInvert(String pkg, boolean v) {
        if (v) sp.edit().putBoolean("invert:" + pkg, true).apply();
        else sp.edit().remove("invert:" + pkg).apply();
    }

    int effectiveMode(String pkg) {
        KompaktSync k = kompakt();
        if (k != null) {
            // Master: our tiles set defaultMode; if KompaktOS' master changed since we last
            // looked (its own tiles/Settings), adopt that.
            if (k.master != null && !k.master.equals(sp.getString(K_LAST_MASTER, null))) {
                sp.edit().putString(K_LAST_MASTER, k.master).apply();
                int mm = Presets.modeFor(k.master);
                if (mm >= 0) setDefaultMode(mm);
            }
            if (pkg != null && k.perApp) {
                int pm = Presets.modeFor(k.appMode.get(pkg));
                if (pm >= 0) return pm;
            }
            return defaultMode();
        }
        int m = pkg == null ? Modes.DEFAULT : appMode(pkg);
        return m == Modes.DEFAULT ? defaultMode() : m;
    }

    boolean weInverted() { return sp.getBoolean(K_WE_INVERTED, false); }
    void setWeInverted(boolean v) { sp.edit().putBoolean(K_WE_INVERTED, v).apply(); }

}
