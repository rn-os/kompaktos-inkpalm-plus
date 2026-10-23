package org.neoport.einkservice;

import android.app.Application;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;

/**
 * Persistent system app: started by the system at boot (android:persistent), before the first unlock
 * (directBootAware). Registers the screen receivers that cannot be declared in the manifest.
 */
public class EinkApplication extends Application {
    @Override public void onCreate() {
        super.onCreate();
        final EinkController ctl = EinkController.get(this);
        ctl.onBoot();
        ForegroundTracker.start(this);

        IntentFilter f = new IntentFilter();
        f.addAction(Intent.ACTION_SCREEN_OFF);
        f.addAction(Intent.ACTION_SCREEN_ON);
        f.addAction(Intent.ACTION_USER_PRESENT);
        registerReceiver(new BroadcastReceiver() {
            @Override public void onReceive(Context c, Intent i) {
                switch (i.getAction()) {
                    case Intent.ACTION_SCREEN_OFF: ctl.onScreenOff(); break;
                    case Intent.ACTION_SCREEN_ON: ctl.onScreenOn(false); break;
                    case Intent.ACTION_USER_PRESENT: ctl.onScreenOn(true); break;
                }
            }
        }, f);
    }
}
