package org.neoport.inkcontrol;

import android.content.BroadcastReceiver;
import android.content.ContentProvider;
import android.content.ContentValues;
import android.content.Context;
import android.content.Intent;
import android.database.Cursor;
import android.database.MatrixCursor;
import android.net.Uri;

/**
 * Public frontlight API so other apps (e.g. the inkpalm+ side panel) can show and change the
 * InkPalm frontlight; InkControl remains the only thing that drives the LEDs (via the bridge).
 *
 * Set (broadcast, all extras optional; levels 0..100):
 *   action  org.neoport.inkcontrol.action.SET_LIGHT   to package org.neoport.inkcontrol
 *   extras  "cold" int, "warm" int, "cold_on" boolean, "warm_on" boolean
 * Read (content provider, one row):
 *   content://org.neoport.inkcontrol.light/state
 *   columns supported(int 0/1), cold, warm (0..100), cold_on, warm_on (0/1), follow_system (0/1)
 * Changes are announced with broadcast org.neoport.inkcontrol.action.LIGHT_CHANGED (no extras;
 * re-query the provider). Clients on Android 11+ need <queries><package android:name=
 * "org.neoport.inkcontrol"/></queries> in their manifest.
 */
final class LightApi {
    static final String ACTION_SET = "org.neoport.inkcontrol.action.SET_LIGHT";
    static final String ACTION_CHANGED = "org.neoport.inkcontrol.action.LIGHT_CHANGED";
    static final Uri STATE = Uri.parse("content://org.neoport.inkcontrol.light/state");

    private LightApi() {}

    static void notifyChanged(Context c) {
        c.getContentResolver().notifyChange(STATE, null);
        c.sendBroadcast(new Intent(ACTION_CHANGED));
    }

    public static class Receiver extends BroadcastReceiver {
        @Override public void onReceive(Context c, Intent i) {
            if (!ACTION_SET.equals(i.getAction()) || !Light.supported()) return;
            if (i.hasExtra("cold")) Light.setLevel(c, Light.COLD, i.getIntExtra("cold", 50));
            if (i.hasExtra("warm")) Light.setLevel(c, Light.WARM, i.getIntExtra("warm", 50));
            if (i.hasExtra("cold_on")) Light.setOn(c, Light.COLD, i.getBooleanExtra("cold_on", true));
            if (i.hasExtra("warm_on")) Light.setOn(c, Light.WARM, i.getBooleanExtra("warm_on", true));
        }
    }

    public static class Provider extends ContentProvider {
        @Override public boolean onCreate() { return true; }

        @Override public Cursor query(Uri u, String[] proj, String sel, String[] args, String sort) {
            Context c = getContext();
            MatrixCursor m = new MatrixCursor(new String[]{
                    "supported", "cold", "warm", "cold_on", "warm_on", "follow_system"});
            m.addRow(new Object[]{Light.supported() ? 1 : 0,
                    Light.level(c, Light.COLD), Light.level(c, Light.WARM),
                    Light.isOn(c, Light.COLD) ? 1 : 0, Light.isOn(c, Light.WARM) ? 1 : 0,
                    Light.followSystem(c) ? 1 : 0});
            m.setNotificationUri(c.getContentResolver(), STATE);
            return m;
        }

        @Override public String getType(Uri u) { return "vnd.android.cursor.item/vnd.org.neoport.inkcontrol.light"; }
        @Override public Uri insert(Uri u, ContentValues v) { return null; }
        @Override public int delete(Uri u, String s, String[] a) { return 0; }
        @Override public int update(Uri u, ContentValues v, String s, String[] a) { return 0; }
    }
}
