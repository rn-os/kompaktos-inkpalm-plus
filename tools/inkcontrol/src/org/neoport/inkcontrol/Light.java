package org.neoport.inkcontrol;

import android.content.Context;
import android.content.SharedPreferences;
import android.provider.Settings;

/**
 * InkPalm Plus frontlight on GSIs (KompaktOS / LineageOS), Boox-style: independent Cold and
 * Warm channels (aw99703 = cold LEDs, aw99703_sec = warm LEDs, 0..2047 each), each with its own
 * on/off and 0..100 level, optionally scaled together by the system brightness slider
 * (Settings.System.SCREEN_BRIGHTNESS), or with Android's adaptive brightness on, by the ambient
 * light sensor (A16's auto brightness never writes SCREEN_BRIGHTNESS, so there is nothing to
 * follow there). Moving a level turns adaptive brightness off: the user's choice wins.
 * Written through the root bridge (light.req) because the
 * /proc nodes are not app-writable. Does nothing on stock Moaan firmware (stock owns the light).
 */
final class Light {
    static final int MAX = 2047;
    static final int COLD = 0, WARM = 1;
    private static final String[] K_LEVEL = {"light_cold", "light_warm"};
    private static final String[] K_ON = {"light_cold_on", "light_warm_on"};
    private static final String K_FOLLOW = "light_follow_system", K_EDGE = "light_edge_swipe";

    private Light() {}

    static boolean supported() {
        return Eink.bridgeAvailable() && new java.io.File("/proc/aw99703").exists();
    }

    private static SharedPreferences sp(Context c) { return new Prefs(c).sp; }

    static int level(Context c, int ch) { return sp(c).getInt(K_LEVEL[ch], 50); }
    static void setLevel(Context c, int ch, int v) {
        sp(c).edit().putInt(K_LEVEL[ch], Math.max(0, Math.min(100, v))).apply();
        if (autoMode(c)) {
            try {   // WRITE_SETTINGS app-op (granted at install, see README)
                Settings.System.putInt(c.getContentResolver(), Settings.System.SCREEN_BRIGHTNESS_MODE,
                        Settings.System.SCREEN_BRIGHTNESS_MODE_MANUAL);
            } catch (SecurityException ignored) {}
        }
        apply(c);
    }
    static boolean isOn(Context c, int ch) { return sp(c).getBoolean(K_ON[ch], true); }
    static void setOn(Context c, int ch, boolean on) { sp(c).edit().putBoolean(K_ON[ch], on).apply(); apply(c); }

    /** Both channels on/off (Quick Settings / panel master switch). */
    static boolean isOn(Context c) { return isOn(c, COLD) || isOn(c, WARM); }
    static void setOn(Context c, boolean on) {
        sp(c).edit().putBoolean(K_ON[COLD], on).putBoolean(K_ON[WARM], on).apply(); apply(c);
    }

    static boolean followSystem(Context c) { return sp(c).getBoolean(K_FOLLOW, true); }
    static void setFollowSystem(Context c, boolean v) { sp(c).edit().putBoolean(K_FOLLOW, v).apply(); apply(c); }
    static boolean edgeSwipe(Context c) { return sp(c).getBoolean(K_EDGE, false); }
    static void setEdgeSwipe(Context c, boolean v) { sp(c).edit().putBoolean(K_EDGE, v).apply(); }

    /** Android's adaptive brightness switch (Settings ▸ Display, or InkPalm+'s Auto pill). */
    static boolean autoMode(Context c) {
        return Settings.System.getInt(c.getContentResolver(), Settings.System.SCREEN_BRIGHTNESS_MODE,
                Settings.System.SCREEN_BRIGHTNESS_MODE_MANUAL) == Settings.System.SCREEN_BRIGHTNESS_MODE_AUTOMATIC;
    }

    /** Scale from the light sensor while in auto mode, or -1 before the first reading. */
    private static volatile float sAutoScale = -1;

    /** Ambient light → scale: dim light in the dark, full from ~300 lux (indoor daylight) up;
     *  log-shaped like the eye. Small changes are ignored so the LEDs don't flicker. */
    static void onLux(Context c, float lux) {
        float f = (float) Math.max(0.1, Math.min(1.0, 0.1 + 0.9 * Math.log10(1 + lux) / Math.log10(301)));
        if (sAutoScale >= 0 && Math.abs(f - sAutoScale) < 0.05f) return;
        sAutoScale = f;
        apply(c);
    }

    static int systemBrightness(Context c) {
        return Settings.System.getInt(c.getContentResolver(), Settings.System.SCREEN_BRIGHTNESS, 128);
    }

    private static int raw(Context c, int ch) {
        if (!isOn(c, ch)) return 0;
        double x = level(c, ch) / 100.0;
        double v = MAX * x * x;                               // gamma 2: finer steps when dim
        if (followSystem(c)) v *= autoMode(c) && sAutoScale >= 0 ? sAutoScale : systemBrightness(c) / 255.0;
        return (int) Math.round(v);
    }

    /** Screen off: LEDs off right away (the driver itself only cuts them at suspend, seconds
     *  later). The saved levels are untouched; {@link #apply} on screen-on restores them. */
    static void screenOff(Context ctx) {
        if (!supported()) return;
        Actions.post(() -> Eink.bridgeWrite("light.req", "light.cold=0\nlight.warm=0\n"));
    }

    /** Pushes the current state to the LEDs. */
    static void apply(Context ctx) {
        if (!supported()) return;
        final Context c = ctx.getApplicationContext();
        Actions.post(() -> {
            Eink.bridgeWrite("light.req", "light.cold=" + raw(c, COLD) + "\nlight.warm=" + raw(c, WARM) + "\n");
            LightApi.notifyChanged(c);   // lets other apps (inkpalm+ side panel) refresh
        });
    }
}
