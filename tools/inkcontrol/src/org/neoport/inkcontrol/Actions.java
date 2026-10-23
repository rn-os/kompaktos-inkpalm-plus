package org.neoport.inkcontrol;

import android.content.Context;
import android.os.Handler;
import android.os.HandlerThread;
import android.provider.Settings;
import android.util.Log;

/** All device-touching work, serialized on one background thread. */
final class Actions {
    private static final String TAG = "InkControl";
    private static HandlerThread sThread;
    private static Handler sHandler;

    /** Mode we last pushed (or null/-1 if unknown); lets us skip redundant writes. */
    static volatile int sCurrentMode = -1;

    private Actions() {}

    private static synchronized Handler h() {
        if (sHandler == null) {
            sThread = new HandlerThread("inkcontrol-worker");
            sThread.start();
            sHandler = new Handler(sThread.getLooper());
        }
        return sHandler;
    }

    static void post(Runnable r) { h().post(r); }

    static void applyMode(final int mode, final boolean force) {
        post(new Runnable() { public void run() {
            if (!force && sCurrentMode == mode) return;
            if (Eink.setMode(mode)) sCurrentMode = mode;
        }});
    }

    /** Package the last foreground switch was for; delayed re-applies check it is still current. */
    private static volatile String sForeground;

    /** Something on the stock firmware resets sys.eink.mode to 7 while an app launches, so the
     *  mode is applied now and re-applied a few times shortly after (only if it was changed). */
    private static final long[] REAPPLY_MS = {300, 800, 1500, 2500, 4000, 6000};

    static void applyForPackage(final Context ctx, final String pkg) {
        final Context app = ctx.getApplicationContext();
        sForeground = pkg;
        post(new Runnable() { public void run() {
            Prefs p = new Prefs(app);
            enforce(p.effectiveMode(pkg));
            // KompaktService's own AppInvert handles invert when we follow its config.
            if (p.kompakt() == null) applyInvert(app, p, p.appInvert(pkg));
        }});
        // Only the stock Moaan firmware resets the mode behind our back; elsewhere (KompaktOS,
        // GSIs) extra writes would just cost repaints, as in KompaktService ("skip unchanged").
        if (!"binder".equals(Eink.backend())) return;
        for (long d : REAPPLY_MS) {
            h().postDelayed(new Runnable() { public void run() {
                if (!pkg.equals(sForeground)) return;
                enforce(new Prefs(app).effectiveMode(pkg));
            }}, d);
        }
    }

    /** The device's mode can't be read (see Eink), so it is simply written each time. */
    private static void enforce(int mode) {
        if (!"binder".equals(Eink.backend()) && mode == sCurrentMode) return;
        if (Eink.setMode(mode)) sCurrentMode = mode;
        else Log.w(TAG, "could not set mode " + mode);
    }

    /** Only touches the setting if we need it on, or if we turned it on earlier. */
    static void applyInvert(Context ctx, Prefs p, boolean want) {
        try {
            android.content.ContentResolver cr = ctx.getContentResolver();
            String key = "accessibility_display_inversion_enabled";
            if (want) {
                if (Settings.Secure.getInt(cr, key, 0) != 1) Settings.Secure.putInt(cr, key, 1);
                p.setWeInverted(true);
            } else if (p.weInverted()) {
                Settings.Secure.putInt(cr, key, 0);
                p.setWeInverted(false);
            }
        } catch (SecurityException e) {
            Log.w(TAG, "WRITE_SECURE_SETTINGS not granted: " + e.getMessage());
        }
    }

    /** Manual full refresh: switch to Full GC16, repaint the screen in it, restore the mode in use.
     *  (The firmware's one_full_mode_timeline counter can't be read by apps, so bumping it
     *  safely isn't possible.) */
    private static volatile long sLastFlash;

    /** Time for a bridge request to reach the HWC (inotifyd + setprop) before repainting. */
    private static final long SETTLE_MS = 250;

    /** Mode tile pressed: apply it and repaint the screen in it, so the change is visible
     *  (a new mode only affects pixels drawn after it, see AppWatcherService.repaint). */
    static void applyModeAndFlash(Context ctx, int mode) {
        post(new Runnable() { public void run() {
            if (Eink.setMode(mode)) sCurrentMode = mode;
            try { Thread.sleep(SETTLE_MS); } catch (InterruptedException ignored) {}
            AppWatcherService.repaint(150);
        }});
    }

    /** The KompaktService overlay appeared: do a real flash (debounced; overlay lasts 480 ms). */
    static void kompaktFlashSeen(Context ctx) {
        long now = android.os.SystemClock.elapsedRealtime();
        if (now - sLastFlash < 2000) return;
        fullRefresh(ctx);
    }

    static void fullRefresh(Context ctx) {
        sLastFlash = android.os.SystemClock.elapsedRealtime();
        final Context app = ctx.getApplicationContext();
        post(new Runnable() { public void run() {
            int back = sCurrentMode >= 0 ? sCurrentMode : new Prefs(app).defaultMode();
            Eink.setMode(2);
            try { Thread.sleep(SETTLE_MS); } catch (InterruptedException ignored) {}
            // Nothing is redrawn without new frames: repaint while Full GC16 is in force.
            AppWatcherService.repaint(150);
            try { Thread.sleep(700); } catch (InterruptedException ignored) {}
            Eink.setMode(back);
            sCurrentMode = back;
        }});
    }
}
