package org.neoport.inkcontrol;

import android.app.AlarmManager;
import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.os.BatteryManager;
import android.os.PowerManager;
import android.os.SystemClock;
import android.util.Log;

/**
 * Auto power-off like the stock Moaan firmware: after the screen has been off for N hours on
 * battery, shut down. A wakeup alarm is armed at screen-off (or unplug while asleep) and
 * cancelled at screen-on / plug-in. Apps may not shut the device down on KompaktOS, so the
 * root bridge does it (power.req, gsi/vendor-fix/eink-apply.sh), which re-checks itself that
 * the screen is off and nothing is plugged in.
 */
final class AutoOff {
    private static final String TAG = "InkControl";
    static final int[] HOURS = {0, 4, 8, 12, 24};
    static final String[] LABELS = {"Never", "After 4 hours asleep", "After 8 hours asleep",
            "After 12 hours asleep", "After 24 hours asleep"};
    private static final String K_HOURS = "auto_off_hours";
    private static final String APPLY = "/system/phh/inkpalm/eink-apply.sh";

    private AutoOff() {}

    /** Needs a bridge new enough to know power.req. */
    static boolean supported() {
        if (!Eink.bridgeAvailable()) return false;
        try {
            return new String(java.nio.file.Files.readAllBytes(new java.io.File(APPLY).toPath()))
                    .contains("power.req");
        } catch (Exception e) {
            return false;
        }
    }

    static int hours(Context c) { return new Prefs(c).sp.getInt(K_HOURS, 0); }
    static void setHours(Context c, int h) {
        new Prefs(c).sp.edit().putInt(K_HOURS, h).apply();
        cancel(c);   // re-armed at the next screen-off
    }

    /** Screen off or charger unplugged: arm the timer if asleep on battery. */
    static void arm(Context c) {
        int h = hours(c);
        if (h <= 0 || !supported() || interactive(c) || plugged(c)) return;
        long at = SystemClock.elapsedRealtime() + h * 3600_000L;
        // Exact + allow-while-idle so Doze can't push it back by hours (targetSdk 30: no
        // SCHEDULE_EXACT_ALARM needed).
        alarms(c).setExactAndAllowWhileIdle(AlarmManager.ELAPSED_REALTIME_WAKEUP, at, pending(c));
        Log.i(TAG, "auto power-off armed: " + h + " h");
    }

    /** Screen on or charger plugged in. */
    static void cancel(Context c) { alarms(c).cancel(pending(c)); }

    private static boolean interactive(Context c) {
        return ((PowerManager) c.getSystemService(Context.POWER_SERVICE)).isInteractive();
    }

    private static boolean plugged(Context c) {
        Intent b = c.getApplicationContext().registerReceiver(null, new IntentFilter(Intent.ACTION_BATTERY_CHANGED));
        return b != null && b.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0) != 0;
    }

    private static AlarmManager alarms(Context c) {
        return (AlarmManager) c.getSystemService(Context.ALARM_SERVICE);
    }

    private static PendingIntent pending(Context c) {
        return PendingIntent.getBroadcast(c.getApplicationContext(), 0,
                new Intent(c.getApplicationContext(), Alarm.class),
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
    }

    /** Timer expired: shut down if still asleep on battery (the bridge checks again). */
    public static class Alarm extends BroadcastReceiver {
        @Override public void onReceive(Context c, Intent i) {
            if (hours(c) <= 0 || interactive(c) || plugged(c)) return;
            Log.i(TAG, "auto power-off: shutting down");
            Eink.bridgeWrite("power.req", "off=1\n");
        }
    }
}
