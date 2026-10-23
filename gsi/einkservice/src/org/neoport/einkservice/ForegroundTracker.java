package org.neoport.einkservice;

import android.app.ActivityManager;
import android.app.ActivityTaskManager;
import android.app.TaskStackListener;
import android.content.Context;
import android.util.Log;

import java.util.List;

/**
 * Foreground package via a task stack listener. Replaces Kompakt's AccessibilityService (EinkAppWatcher), which on
 * a GSI would need to be enabled via Settings.Secure and shows up in Safety Center. Hidden API: needs
 * platform_apis + android.permission.MANAGE_ACTIVITY_TASKS (UNVERIFIED that it compiles unchanged on Android 14/16;
 * on failure, fall back to Kompakt's AccessibilityService approach, see DESIGN.md).
 */
final class ForegroundTracker {
    private static final String TAG = EinkController.TAG;

    private ForegroundTracker() {}

    static void start(Context c) {
        final EinkController ctl = EinkController.get(c);
        try {
            ActivityTaskManager.getService().registerTaskStackListener(new TaskStackListener() {
                @Override public void onTaskStackChanged() { check(c, ctl); }
                @Override public void onTaskMovedToFront(android.app.ActivityManager.RunningTaskInfo t) { check(c, ctl); }
            });
            Log.i(TAG, "task stack listener registered");
        } catch (Throwable t) {
            Log.e(TAG, "cannot register task stack listener: " + t);
        }
    }

    private static void check(Context c, EinkController ctl) {
        try {
            ActivityManager am = c.getSystemService(ActivityManager.class);
            @SuppressWarnings("deprecation")
            List<ActivityManager.RunningTaskInfo> l = am.getRunningTasks(1);
            if (l == null || l.isEmpty() || l.get(0).topActivity == null) return;
            String pkg = l.get(0).topActivity.getPackageName();
            if (pkg.equals(c.getPackageName())) return;   // our own flash window is never an app switch
            ctl.onForeground(pkg);
        } catch (Throwable t) {
            Log.w(TAG, "top activity unavailable: " + t);
        }
    }
}
