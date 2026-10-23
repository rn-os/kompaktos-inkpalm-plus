package org.neoport.einkservice;

import android.content.Context;
import android.provider.Settings;
import android.util.Log;

/** Per-app colour inversion: ported from KompaktService AppInvert.kt. Only ever undoes an inversion it made. */
final class AppInvert {
    private static final String SETTING = Settings.Secure.ACCESSIBILITY_DISPLAY_INVERSION_ENABLED;

    private AppInvert() {}

    static void apply(Context c, EinkPrefs prefs, String pkg) {
        try {
            boolean on = Settings.Secure.getInt(c.getContentResolver(), SETTING, 0) == 1;
            if (prefs.invertWanted(pkg)) {
                if (!on) {
                    Settings.Secure.putInt(c.getContentResolver(), SETTING, 1);
                    prefs.setInvertOurs(true);
                }
            } else if (prefs.invertOurs()) {
                if (on) Settings.Secure.putInt(c.getContentResolver(), SETTING, 0);
                prefs.setInvertOurs(false);
            }
        } catch (Throwable t) {
            Log.w(EinkController.TAG, "invert: " + t);
        }
    }
}
