package org.neoport.inkcontrol;

import android.accessibilityservice.AccessibilityService;
import android.view.View;
import android.view.accessibility.AccessibilityEvent;
import android.view.inputmethod.InputMethodInfo;
import android.view.inputmethod.InputMethodManager;

import java.util.HashSet;
import java.util.List;
import java.util.Set;

/** Applies per-app e-ink mode + inversion when the foreground app changes. */
public class AppWatcherService extends AccessibilityService {
    private String last;
    private final Set<String> ignored = new HashSet<>();

    /** The stock SystemUI forces sys.eink.mode=7 each time the window manager publishes a new
     *  Settings.Global top_packagename (RootWindowContainer.allResumedActivitiesIdle ->
     *  EinkSettingsProvider.query -> setEinkMode("7")). Watching that key catches every reset,
     *  including late ones not tied to a window-state event. */
    private android.database.ContentObserver topObserver, brightnessObserver, autoObserver;
    private final android.content.BroadcastReceiver screenReceiver = new android.content.BroadcastReceiver() {
        @Override public void onReceive(android.content.Context c, android.content.Intent i) {
            switch (i.getAction()) {
                case android.content.Intent.ACTION_SCREEN_OFF: Light.screenOff(c); syncLightSensor(); AutoOff.arm(c); break;
                case android.content.Intent.ACTION_SCREEN_ON: Light.apply(c); syncLightSensor(); AutoOff.cancel(c); break;
                case android.content.Intent.ACTION_POWER_CONNECTED: AutoOff.cancel(c); break;
                case android.content.Intent.ACTION_POWER_DISCONNECTED: AutoOff.arm(c); break;
            }
        }
    };

    @Override protected void onServiceConnected() {
        super.onServiceConnected();
        topObserver = new android.database.ContentObserver(new android.os.Handler()) {
            @Override public void onChange(boolean self) {
                String top = android.provider.Settings.Global.getString(
                        getContentResolver(), "top_packagename");
                if (top != null && !ignored.contains(top)) Actions.applyForPackage(AppWatcherService.this, top);
            }
        };
        getContentResolver().registerContentObserver(
                android.provider.Settings.Global.getUriFor("top_packagename"), false, topObserver);
        // Frontlight follows the system brightness slider (GSIs; no-op on stock).
        brightnessObserver = new android.database.ContentObserver(new android.os.Handler()) {
            @Override public void onChange(boolean self) { Light.apply(AppWatcherService.this); }
        };
        getContentResolver().registerContentObserver(android.provider.Settings.System.getUriFor(
                android.provider.Settings.System.SCREEN_BRIGHTNESS), false, brightnessObserver);
        // Adaptive brightness on/off (Settings or InkPalm+'s Auto pill): start/stop our sensor.
        autoObserver = new android.database.ContentObserver(new android.os.Handler()) {
            @Override public void onChange(boolean self) { syncLightSensor(); Light.apply(AppWatcherService.this); }
        };
        getContentResolver().registerContentObserver(android.provider.Settings.System.getUriFor(
                android.provider.Settings.System.SCREEN_BRIGHTNESS_MODE), false, autoObserver);
        Light.apply(this);
        sInstance = this;
        syncLightSensor();
        syncEdgeStrips();
        // Frontlight follows the screen: off immediately at sleep, restored at wake (the LED
        // driver drops its levels across suspend and nothing else rewrites them).
        android.content.IntentFilter f = new android.content.IntentFilter(android.content.Intent.ACTION_SCREEN_OFF);
        f.addAction(android.content.Intent.ACTION_SCREEN_ON);
        // Auto power-off timer runs only while asleep on battery (AutoOff).
        f.addAction(android.content.Intent.ACTION_POWER_CONNECTED);
        f.addAction(android.content.Intent.ACTION_POWER_DISCONNECTED);
        registerReceiver(screenReceiver, f);
        ignored.add("android");
        ignored.add("com.android.systemui");
        ignored.add("com.android.permissioncontroller");
        ignored.add("com.google.android.permissioncontroller");
        try {
            InputMethodManager imm = (InputMethodManager) getSystemService(INPUT_METHOD_SERVICE);
            List<InputMethodInfo> l = imm.getInputMethodList();
            for (InputMethodInfo i : l) ignored.add(i.getPackageName());
        } catch (Throwable ignoredErr) {}
        last = null;
    }

    @Override public void onAccessibilityEvent(AccessibilityEvent e) {
        if (e.getEventType() != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return;
        CharSequence cs = e.getPackageName();
        if (cs == null) return;
        String pkg = cs.toString();
        if (pkg.equals("com.kompakt.service")) {
            // KompaktOS refresh/flush (QS tile, long-press Home, mode tile) shows a bare black
            // View overlay; its sysfs "clear" does nothing here, so make it a real flash.
            if (View.class.getName().contentEquals(String.valueOf(e.getClassName()))
                    && new Prefs(this).flashOnKompaktRefresh()) Actions.kompaktFlashSeen(this);
            return;
        }
        if (ignored.contains(pkg)) return;
        // Overlays, panels and popups (e.g. a quick-panel service window) also send
        // TYPE_WINDOW_STATE_CHANGED; only a real Activity means the foreground app changed.
        if (!isActivity(pkg, e.getClassName())) return;
        // Also re-checked on screen changes inside the same app: the firmware resets the
        // mode on those too. Actions only writes when the device is in the wrong mode.
        last = pkg;
        Actions.applyForPackage(this, pkg);
    }

    private boolean isActivity(String pkg, CharSequence cls) {
        if (cls == null) return false;
        try {
            getPackageManager().getActivityInfo(
                    new android.content.ComponentName(pkg, cls.toString()), 0);
            return true;
        } catch (android.content.pm.PackageManager.NameNotFoundException notActivity) {
            return false;
        }
    }

    // ---- Auto frontlight: ambient light sensor while adaptive brightness is on (see Light) ----
    private boolean luxListening;
    private final android.hardware.SensorEventListener luxListener = new android.hardware.SensorEventListener() {
        @Override public void onSensorChanged(android.hardware.SensorEvent e) { Light.onLux(AppWatcherService.this, e.values[0]); }
        @Override public void onAccuracyChanged(android.hardware.Sensor sensor, int accuracy) {}
    };

    /** Listens only while the screen is on and adaptive brightness is on (the LEDs are off
     *  while asleep anyway). */
    private void syncLightSensor() {
        android.hardware.SensorManager sm = (android.hardware.SensorManager) getSystemService(SENSOR_SERVICE);
        boolean want = Light.supported() && Light.autoMode(this)
                && ((android.os.PowerManager) getSystemService(POWER_SERVICE)).isInteractive();
        if (want == luxListening || sm == null) return;
        android.hardware.Sensor light = sm.getDefaultSensor(android.hardware.Sensor.TYPE_LIGHT);
        if (want && light != null) {
            luxListening = sm.registerListener(luxListener, light, android.hardware.SensorManager.SENSOR_DELAY_NORMAL);
        } else if (!want) {
            sm.unregisterListener(luxListener);
            luxListening = false;
        }
    }

    // ---- Repaint: makes a mode change visible ----------------------------------------------
    /** The panel only redraws pixels that change, and in the mode current at that moment, so a
     *  new sys.eink.mode doesn't show on a static screen. A brief full-screen white overlay makes
     *  every non-white pixel change twice, redrawing the whole screen in the current mode.
     *  Returns false (no-op) if the service isn't running. Any thread. */
    static boolean repaint(long holdMs) {
        AppWatcherService s = sInstance;
        if (s == null) return false;
        s.main.post(() -> {
            android.view.WindowManager wm = (android.view.WindowManager) s.getSystemService(WINDOW_SERVICE);
            android.view.View v = new android.view.View(s);
            v.setBackgroundColor(0xffffffff);
            android.view.WindowManager.LayoutParams lp = new android.view.WindowManager.LayoutParams(
                    android.view.ViewGroup.LayoutParams.MATCH_PARENT, android.view.ViewGroup.LayoutParams.MATCH_PARENT,
                    android.view.WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
                    android.view.WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
                            | android.view.WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE
                            | android.view.WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN
                            | android.view.WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
                    android.graphics.PixelFormat.OPAQUE);
            try { wm.addView(v, lp); } catch (Exception e) { return; }
            s.main.postDelayed(() -> { try { wm.removeView(v); } catch (Exception ignored) {} }, holdMs);
        });
        return true;
    }

    private final android.os.Handler main = new android.os.Handler(android.os.Looper.getMainLooper());

    // ---- Boox-style edge swipe for the frontlight (optional, see FrontlightPanel) ----------
    private static AppWatcherService sInstance;
    private final android.view.View[] edgeStrips = new android.view.View[2];

    /** Adds/removes the edge strips to match the setting (callable from the panel). */
    static void refreshEdgeStrips() {
        AppWatcherService s = sInstance;
        if (s != null) s.syncEdgeStrips();
    }

    private void syncEdgeStrips() {
        boolean want = Light.supported() && Light.edgeSwipe(this);
        android.view.WindowManager wm = (android.view.WindowManager) getSystemService(WINDOW_SERVICE);
        for (int ch = 0; ch < 2; ch++) {
            if (!want && edgeStrips[ch] != null) {
                try { wm.removeView(edgeStrips[ch]); } catch (Exception ignored) {}
                edgeStrips[ch] = null;
            } else if (want && edgeStrips[ch] == null) {
                edgeStrips[ch] = newStrip(ch);
                wm.addView(edgeStrips[ch], stripParams(ch));
            }
        }
    }

    private android.view.WindowManager.LayoutParams stripParams(int ch) {
        float dp = getResources().getDisplayMetrics().density;
        int h = getResources().getDisplayMetrics().heightPixels;
        android.view.WindowManager.LayoutParams lp = new android.view.WindowManager.LayoutParams(
                Math.round(14 * dp), h / 2,   // middle half of the edge: leaves room for back gestures
                android.view.WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
                android.view.WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
                        | android.view.WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
                android.graphics.PixelFormat.TRANSLUCENT);
        lp.gravity = (ch == Light.COLD ? android.view.Gravity.LEFT : android.view.Gravity.RIGHT)
                | android.view.Gravity.CENTER_VERTICAL;
        return lp;
    }

    /** Vertical drag on the strip: up = brighter. The whole strip height spans 0..100%. */
    private android.view.View newStrip(int ch) {
        android.view.View v = new android.view.View(this);
        v.setOnTouchListener(new android.view.View.OnTouchListener() {
            float downY; int start; int last = -1;
            @Override public boolean onTouch(android.view.View view, android.view.MotionEvent e) {
                switch (e.getActionMasked()) {
                    case android.view.MotionEvent.ACTION_DOWN:
                        downY = e.getRawY(); start = Light.level(AppWatcherService.this, ch); last = start; return true;
                    case android.view.MotionEvent.ACTION_MOVE:
                        last = Math.max(0, Math.min(100, start + Math.round((downY - e.getRawY()) * 100f / view.getHeight())));
                        return true;
                    case android.view.MotionEvent.ACTION_UP:
                        if (last != start) {
                            if (!Light.isOn(AppWatcherService.this, ch)) Light.setOn(AppWatcherService.this, ch, true);
                            Light.setLevel(AppWatcherService.this, ch, last);
                            android.widget.Toast.makeText(AppWatcherService.this,
                                    (ch == Light.COLD ? "Cold light " : "Warm light ") + last + "%",
                                    android.widget.Toast.LENGTH_SHORT).show();
                        }
                        return true;
                    default:
                        return true;
                }
            }
        });
        return v;
    }

    @Override public void onDestroy() {
        sInstance = null;
        try { unregisterReceiver(screenReceiver); } catch (Exception ignored) {}
        android.view.WindowManager wm = (android.view.WindowManager) getSystemService(WINDOW_SERVICE);
        for (android.view.View v : edgeStrips) if (v != null) try { wm.removeView(v); } catch (Exception ignored) {}
        if (topObserver != null) getContentResolver().unregisterContentObserver(topObserver);
        if (brightnessObserver != null) getContentResolver().unregisterContentObserver(brightnessObserver);
        if (autoObserver != null) getContentResolver().unregisterContentObserver(autoObserver);
        ((android.hardware.SensorManager) getSystemService(SENSOR_SERVICE)).unregisterListener(luxListener);
        super.onDestroy();
    }

    @Override public void onInterrupt() {}
}
