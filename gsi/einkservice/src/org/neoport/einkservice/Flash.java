package org.neoport.einkservice;

import android.content.Context;
import android.graphics.Color;
import android.graphics.PixelFormat;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import android.view.View;
import android.view.WindowManager;

/** Ghosting flush by overlay: ported from KompaktService Flash.kt. Fallback when the native full frame is unavailable. */
final class Flash {
    private static final long FLASH_MS = 480L;   // Kompakt: two panel paints, so one always catches it
    private static final Handler H = new Handler(Looper.getMainLooper());
    private static volatile View showing;

    private Flash() {}

    static boolean active() { return showing != null; }

    static void show(Context c) {
        H.post(() -> {
            if (showing != null) return;
            WindowManager wm = c.getSystemService(WindowManager.class);
            if (wm == null) return;
            View v = new View(c);
            v.setBackgroundColor(Color.BLACK);
            WindowManager.LayoutParams lp = new WindowManager.LayoutParams(
                    WindowManager.LayoutParams.MATCH_PARENT, WindowManager.LayoutParams.MATCH_PARENT,
                    WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
                    WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE | WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE
                            | WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL
                            | WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN
                            | WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
                    PixelFormat.OPAQUE);
            lp.windowAnimations = 0;
            lp.layoutInDisplayCutoutMode = WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_ALWAYS;
            lp.setTitle("InkPalmEinkFlash");
            try {
                wm.addView(v, lp);
                showing = v;
            } catch (Throwable t) {
                Log.w(EinkController.TAG, "flash: cannot add overlay: " + t);
                return;
            }
            H.postDelayed(() -> hide(c), FLASH_MS);
        });
    }

    private static void hide(Context c) {
        View v = showing;
        if (v == null) return;
        showing = null;
        try {
            c.getSystemService(WindowManager.class).removeViewImmediate(v);
        } catch (Throwable t) {
            Log.w(EinkController.TAG, "flash: cannot remove overlay: " + t);
        }
    }
}
