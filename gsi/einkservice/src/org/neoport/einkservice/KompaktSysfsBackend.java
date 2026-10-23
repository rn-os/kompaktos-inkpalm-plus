package org.neoport.einkservice;

import android.util.Log;

import java.io.File;
import java.io.FileWriter;
import java.io.IOException;

/**
 * Mudita Kompakt backend, ported from KompaktService Hardware.kt (object Eink). Kept so the app can be
 * built for either panel; not used on the InkPalm. Presets copied from Kompakt; "auto" needs Kompakt's own
 * kernel module (KAUTO waveform) and falls back to quality when the read-back differs.
 */
final class KompaktSysfsBackend implements EinkBackend {
    private static final String TAG = "InkPalmEink";
    private static final String E = "/sys/einkinfo";

    private static final class P {
        final String wf; final int bpp, gamma; final float bright, contrast; final int dither;
        P(String wf, int bpp, int gamma, float bright, float contrast, int dither) {
            this.wf = wf; this.bpp = bpp; this.gamma = gamma; this.bright = bright; this.contrast = contrast; this.dither = dither;
        }
    }

    private static P preset(String key) {
        switch (key) {
            case "fast": return new P("A2", 1, 1, 1.0f, 1.0f, 0);
            case "soft": return new P("A2", 1, 3, 1.0f, 0.8f, 0);
            case "fastdither": return new P("A2", 1, 1, 1.0f, 1.2f, 96);
            case "text": return new P("GL16", 4, 1, 1.0f, 1.2f, 0);
            case "auto": return new P("KAUTO", 4, 2, 1.0f, 1.0f, 0);
            default: return new P("GL16", 4, 2, 1.0f, 1.0f, 0); // quality
        }
    }

    @Override public String name() { return "kompakt-sysfs"; }
    @Override public boolean available() { return new File(E + "/waveform_mode").canWrite(); }
    @Override public void applyBootDefaults(EinkPrefs prefs) { applyMode(EinkModes.get(prefs.globalMode()), prefs); }

    @Override public void applyMode(EinkModes.Mode m, EinkPrefs prefs) {
        P p = preset(m.key);
        write("waveform_mode", p.wf);
        write("pixelbits", Integer.toString(p.bpp));
        write("gamma", Integer.toString(p.gamma));
        write("brightness", Integer.toString(Math.round(p.bright * 100f)));
        write("contrast", Integer.toString(Math.round(p.contrast * 10f)));
        if (p.dither <= 0) {
            write("dither_type", "0");
        } else {
            write("dither_param", Integer.toString(p.dither));
            write("dither_type", "4");
        }
    }

    @Override public boolean fullRefresh() { return write("clear", "1"); }

    @Override public void onScreenState(boolean interactive, EinkPrefs prefs) { /* Kompakt's kernel handles sleep */ }

    private static boolean write(String node, String v) {
        try (FileWriter w = new FileWriter(E + "/" + node)) {
            w.write(v + "\n");
            return true;
        } catch (IOException e) {
            Log.w(TAG, "write failed " + node + "=" + v + ": " + e);
            return false;
        }
    }
}
