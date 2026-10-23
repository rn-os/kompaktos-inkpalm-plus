package org.neoport.einkservice;

import android.content.Context;
import android.os.Handler;
import android.os.HandlerThread;
import android.os.Looper;
import android.util.Log;

/**
 * Single entry point. All backend I/O runs on one worker thread so property writes never block the UI
 * and ordering is preserved (Kompakt used a single-thread executor for the same reason).
 */
final class EinkController {
    static final String TAG = "InkPalmEink";
    private static EinkController sInstance;

    final Context context;
    final EinkPrefs prefs;
    final EinkBackend backend;
    private final Handler worker;
    private final Handler main = new Handler(Looper.getMainLooper());

    private volatile String appliedKey;
    private volatile String foreground;

    static synchronized EinkController get(Context c) {
        if (sInstance == null) sInstance = new EinkController(c.getApplicationContext());
        return sInstance;
    }

    private EinkController(Context c) {
        context = c;
        prefs = new EinkPrefs(c);
        backend = EinkBackends.select();
        HandlerThread t = new HandlerThread("eink-io");
        t.start();
        worker = new Handler(t.getLooper());
        Log.i(TAG, "backend=" + backend.name());
    }

    /** Boot: stock firmware wrote these implicitly via SystemUI/EinkService. */
    void onBoot() {
        worker.post(() -> {
            backend.applyBootDefaults(prefs);
            appliedKey = prefs.globalMode();
        });
    }

    String currentPackage() { return foreground; }

    /** Foreground app changed (from ForegroundTracker). */
    void onForeground(String pkg) {
        if (pkg == null || pkg.equals(foreground)) return;
        foreground = pkg;
        AppInvert.apply(context, prefs, pkg);
        if (!prefs.perApp()) return;
        applyKey(prefs.appMode(pkg), false);
    }

    void setGlobalMode(String key) {
        prefs.setGlobalMode(key);
        String pkg = foreground;
        applyKey(pkg != null ? prefs.appMode(pkg) : key, true);
    }

    /** Re-apply the mode for the app in front (after screen on, window changes the vendor may reset, etc.). */
    void reapply() {
        String pkg = foreground;
        applyKey(pkg != null ? prefs.appMode(pkg) : prefs.globalMode(), true);
    }

    private void applyKey(String key, boolean force) {
        worker.post(() -> {
            if (!force && key.equals(appliedKey)) return;   // writing an unchanged mode can force a repaint
            appliedKey = key;
            backend.applyMode(EinkModes.get(key), prefs);
        });
    }

    String appliedKey() { return appliedKey; }

    /** Long-press home / tile / unlock. Style per prefs; always ends with the user's mode restored. */
    void fullRefresh() {
        switch (prefs.refreshStyle()) {
            case "overlay":
                Flash.show(context);
                break;
            case "mode2":
                worker.post(this::flashMode2);
                break;
            default:
                worker.post(() -> {
                    if (!backend.fullRefresh()) Flash.show(context);
                });
        }
    }

    /** InkControl's verified fallback: Full GC16 (2) for 700 ms, then restore. Rockchip only. */
    private void flashMode2() {
        if (!(backend instanceof RkEinkBackend)) return;
        backend.applyMode(new EinkModes.Mode("full", "Full", EinkModes.EPD_FULL_GC16, null), prefs);
        worker.postDelayed(() -> {
            String k = appliedKey != null ? appliedKey : prefs.globalMode();
            backend.applyMode(EinkModes.get(k), prefs);
        }, 700);
    }

    void onScreenOff() {
        worker.post(() -> backend.onScreenState(false, prefs));
    }

    /** Screen on / user present: leave standby, restore the mode, and de-ghost what the sleep image left. */
    void onScreenOn(boolean unlocked) {
        worker.post(() -> backend.onScreenState(true, prefs));
        reapply();
        if (unlocked && prefs.unlockRefresh()) {
            // One frame for the panel to finish painting the unlocked screen first (Kompakt: DELAY_MS = 150).
            main.postDelayed(this::fullRefresh, 150);
        }
    }
}
