package org.neoport.inkcontrol;

import android.app.Application;

/** Gives {@link Eink} the app's private files dir (where the GSI e-ink bridge reads requests). */
public class App extends Application {
    @Override public void onCreate() {
        super.onCreate();
        Eink.setFilesDir(getFilesDir());
    }
}
