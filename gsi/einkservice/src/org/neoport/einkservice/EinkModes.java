package org.neoport.einkservice;

import java.util.LinkedHashMap;

/**
 * Abstract presets (same keys as KompaktService: fast, soft, fastdither, text, quality, auto) mapped to
 * Rockchip EBC mode ids (android.os.EinkManager.EinkMode, recovered from stock framework.jar; see
 * tools/inkcontrol/README.md). The mapping to Kompakt's waveform presets is by intent, NOT verified on the panel.
 */
final class EinkModes {
    private EinkModes() {}

    static final int EPD_FULL_GC16 = 2;
    static final int EPD_PART_GC16 = 7;   // stock default
    static final int EPD_PART_GL16 = 8;
    static final int EPD_A2 = 12;
    static final int EPD_A2_DITHER = 13;
    static final int EPD_DU = 14;
    static final int EPD_AUTO_DU = 22;

    static final class Mode {
        final String key;
        final String label;
        final int rk;
        /** Value for debug.sf.gamma.gamma, or null to leave the global setting alone. */
        final String rkGamma;

        Mode(String key, String label, int rk, String rkGamma) {
            this.key = key; this.label = label; this.rk = rk; this.rkGamma = rkGamma;
        }
    }

    static final LinkedHashMap<String, Mode> ALL = new LinkedHashMap<>();
    static {
        add("fast", "Fast", EPD_A2);
        add("fastdither", "Fast + dither", EPD_A2_DITHER);
        add("soft", "Fast, soft", EPD_DU);
        add("text", "Text", EPD_PART_GL16);
        add("quality", "Quality", EPD_PART_GC16);
        add("auto", "Auto", EPD_AUTO_DU);
    }

    private static void add(String k, String l, int rk) { ALL.put(k, new Mode(k, l, rk, null)); }

    /** Stock behaviour: every app starts at mode 7. */
    static final String DEFAULT = "quality";

    static Mode get(String key) {
        Mode m = ALL.get(key);
        return m != null ? m : ALL.get(DEFAULT);
    }

    static String[] keys() { return ALL.keySet().toArray(new String[0]); }

    static String next(String cur) {
        String[] k = keys();
        for (int i = 0; i < k.length; i++) if (k[i].equals(cur)) return k[(i + 1) % k.length];
        return k[0];
    }
}
