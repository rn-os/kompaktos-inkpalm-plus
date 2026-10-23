package org.neoport.inkcontrol;

/**
 * KompaktOS e-ink presets (KompaktService Eink.MODES: fast, soft, fastdither, text, quality, auto)
 * mapped to the InkPalm's sys.eink.mode values. KompaktOS presets are sysfs waveform + gamma +
 * contrast + dither bundles on the Kompakt's MediaTek panel; here only the waveform class can be
 * reproduced, so the mapping is by intent:
 *   fast       A2 1bpp                              -> 12 EPD_A2
 *   soft       A2, softer gamma/contrast            -> 14 EPD_DU (b/w, less harsh than A2)
 *   fastdither A2 + 96-level dither (KompaktOS default) -> 13 EPD_A2_DITHER
 *   text       GL16 4bpp, high contrast             -> 8  EPD_PART_GL16
 *   quality    GL16 4bpp                            -> 7  EPD_PART_GC16 (stock default)
 *   auto       kernel switches A2 / GL16            -> 22 EPD_AUTO_DU (vendor HWC auto)
 */
final class Presets {
    static final String[] KEYS = {"fast", "soft", "fastdither", "text", "quality", "auto"};
    static final String[] LABELS = {"Fast", "Fast, soft", "Fast + dither", "Text", "Quality", "Auto"};
    /** Words drawn as the QS tile icons (KompaktOS shows tiles icon-only). */
    static final String[] ICON_TEXT = {"FAST", "FAST\nSOFT", "FAST\nDITHER", "TEXT", "QUALITY", "AUTO"};
    static final int[] MODES = {12, 14, 13, 8, 7, 22};

    private Presets() {}

    static int modeFor(String key) {
        for (int i = 0; i < KEYS.length; i++) if (KEYS[i].equals(key)) return MODES[i];
        return -1;
    }

    static int indexOfMode(int mode) {
        for (int i = 0; i < MODES.length; i++) if (MODES[i] == mode) return i;
        return -1;
    }

    static String labelForMode(int mode) {
        int i = indexOfMode(mode);
        return i < 0 ? null : LABELS[i];
    }
}
