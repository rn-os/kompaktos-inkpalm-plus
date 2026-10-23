package org.neoport.einkservice;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.util.Log;

/**
 * Manifest receiver:
 *  - BOOT_COMPLETED: re-apply defaults once vendor init has finished (it may overwrite sys.eink.*).
 *  - ACTION_REFRESH: long-press-home hook (KompaktOS frameworks_base patches 0016/0035, retarget the action).
 *  - ACTION_SET_MODE: adb/debug entry, protected by android.permission.DUMP so only shell/system can call it:
 *      adb shell am broadcast -a org.neoport.einkservice.SET_MODE --es mode text -p org.neoport.einkservice
 *      adb shell am broadcast -a org.neoport.einkservice.SET_APP_MODE --es pkg org.koreader.launcher.fdroid --es mode text ...
 *      adb shell am broadcast -a org.neoport.einkservice.SET_PREF --es key rk_fullmode_cnt --es value 20 ...
 */
public class EinkReceiver extends BroadcastReceiver {
    static final String ACTION_REFRESH = "org.neoport.einkservice.action.REFRESH";
    static final String ACTION_SET_MODE = "org.neoport.einkservice.SET_MODE";
    static final String ACTION_SET_APP_MODE = "org.neoport.einkservice.SET_APP_MODE";
    static final String ACTION_SET_PREF = "org.neoport.einkservice.SET_PREF";

    @Override public void onReceive(Context c, Intent i) {
        EinkController ctl = EinkController.get(c);
        String a = i.getAction();
        if (a == null) return;
        switch (a) {
            case Intent.ACTION_LOCKED_BOOT_COMPLETED:
            case Intent.ACTION_BOOT_COMPLETED:
                ctl.onBoot();
                break;
            case ACTION_REFRESH:
                ctl.fullRefresh();
                break;
            case ACTION_SET_MODE: {
                String m = i.getStringExtra("mode");
                if (m != null && EinkModes.ALL.containsKey(m)) ctl.setGlobalMode(m);
                break;
            }
            case ACTION_SET_APP_MODE: {
                String p = i.getStringExtra("pkg");
                String m = i.getStringExtra("mode");   // absent/"-" clears
                if (p != null) ctl.prefs.setAppMode(p, m != null && EinkModes.ALL.containsKey(m) ? m : null);
                break;
            }
            case ACTION_SET_PREF: {
                String k = i.getStringExtra("key"), v = i.getStringExtra("value");
                if (k != null && v != null) {
                    if (v.equals("true") || v.equals("false")) ctl.prefs.putBool(k, v.equals("true"));
                    else ctl.prefs.putString(k, v);
                    ctl.onBoot();   // push Rockchip extras (fullmode_cnt, gamma, ...) to the panel
                }
                break;
            }
            default:
                Log.w(EinkController.TAG, "unknown action " + a);
        }
    }
}
