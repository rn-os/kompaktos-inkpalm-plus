package org.neoport.inkcontrol;

/** EPD mode ids = android.os.EinkManager$EinkMode string constants (value of sys.eink.mode). */
final class Modes {
    static final int DEFAULT = -100; // "use global default" sentinel (never sent to device)

    static final int[] VALUES = {
        DEFAULT, 0, 7, 8, 9, 10, 11, 2, 3, 4, 5, 6, 14, 15, 12, 13, 22, 23,
    };
    static final String[] LABELS = {
        "Default (global)",
        "0 Auto",
        "Quality: 7 Partial GC16 (stock default)",
        "Text: 8 Partial GL16",
        "9 Partial GLR16",
        "10 Partial GLD16",
        "11 Partial GCC16 (colour)",
        "2 Full GC16 (flashes)",
        "3 Full GL16",
        "4 Full GLR16",
        "5 Full GLD16",
        "6 Full GCC16",
        "Fast, soft: 14 DU (fast black/white)",
        "15 DU4 (fast 4-level)",
        "Fast: 12 A2 (fastest, ghosty)",
        "Fast + dither: 13 A2 dither",
        "Auto: 22 Auto + DU",
        "23 Auto + DU4",
    };

    /** Order used by the mode-cycling tile. */
    static final int[] CYCLE = Presets.MODES; // KompaktOS order: Fast, Fast soft, Fast+dither, Text, Quality, Auto

    static int indexOf(int value) {
        for (int i = 0; i < VALUES.length; i++) if (VALUES[i] == value) return i;
        return 0;
    }

    static String shortName(int v) {
        String preset = Presets.labelForMode(v);
        if (preset != null) return preset;
        switch (v) {
            case 0: return "Auto";
            case 2: return "Full GC16";
            case 3: return "Full GL16";
            case 4: return "Full GLR16";
            case 5: return "Full GLD16";
            case 6: return "Full GCC16";
            case 7: return "Quality (GC16)";
            case 8: return "Text (GL16)";
            case 9: return "GLR16";
            case 10: return "GLD16";
            case 11: return "GCC16";
            case 12: return "A2 fastest";
            case 13: return "A2 dither";
            case 14: return "DU fast";
            case 15: return "DU4";
            case 22: return "Auto+DU";
            case 23: return "Auto+DU4";
            default: return "mode " + v;
        }
    }

    private Modes() {}
}
