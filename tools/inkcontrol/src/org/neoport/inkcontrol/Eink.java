package org.neoport.inkcontrol;

import android.os.IBinder;
import android.os.Parcel;
import android.os.RemoteException;
import android.util.Log;

import java.lang.reflect.Method;

/**
 * Minimal client for the stock Moaan "eink" binder service (android.os.IEinkManager).
 *
 * We do not link against the hidden AIDL class. We fetch the IBinder and speak the
 * wire protocol directly (recovered from IEinkManager$Stub in framework.jar):
 *   descriptor "android.os.IEinkManager"
 *   1 init():int  2 kill():int  3 standby():int  4 quitStandby():int
 *   5 setProperty(String key, String value):void
 * Everything useful (mode switching, full refresh) is a setProperty() call.
 * sys.eink.* is labelled vendor_ebook_prop, which apps may write through this service
 * but cannot READ, so the current mode is never known here.
 */
final class Eink {
    private static final String TAG = "InkControl";
    private static final String DESCRIPTOR = "android.os.IEinkManager";
    private static final int TX_SET_PROPERTY = 5;

    static final String PROP_MODE = "sys.eink.mode";

    private static IBinder sBinder;
    private static boolean sExemptionTried;
    private static boolean sMissingLogged;

    private Eink() {}

    /** Setting mode: value is the decimal string of an EPD_* constant, see {@link Modes}. */
    static synchronized boolean setMode(int mode) {
        return setProperty(PROP_MODE, Integer.toString(mode));
    }

    static synchronized boolean isAvailable() {
        return !"none".equals(backend());
    }

    /** "binder" on stock Moaan firmware, "direct" on a GSI with our platform key,
     *  "bridge" on a GSI carrying the InkPalm e-ink bridge, else "none". */
    static synchronized String backend() {
        if (binder() != null) return "binder";
        if (directSetAllowed()) return "direct";
        return bridgeAvailable() ? "bridge" : "none";
    }

    /**
     * GSIs signed with keys we don't have (e.g. release-keys builds): a root helper baked into
     * the image (gsi/vendor-fix/eink-bridge.sh) watches files/eink.req and applies whitelisted
     * sys.eink.* values. Requests are "key=value" lines.
     */
    private static final java.io.File BRIDGE = new java.io.File("/system/phh/inkpalm/eink-bridge.sh");
    private static java.io.File sFilesDir;

    static void setFilesDir(java.io.File dir) { sFilesDir = dir; }

    /** The root bridge is baked into the image (any backend: a platform-signed build still needs it
     *  for the frontlight, sleep image and power-off until our sepolicy covers those). */
    static boolean bridgeAvailable() {
        return sFilesDir != null && BRIDGE.exists();
    }

    private static boolean bridgeSet(String key, String value) {
        return bridgeWrite("eink.req", key + "=" + value + "\n");
    }

    /** Writes one request file for the root bridge (eink.req, light.req); see eink-apply.sh. */
    static synchronized boolean bridgeWrite(String file, String content) {
        if (!bridgeAvailable()) return false;
        try (java.io.FileOutputStream out =
                     new java.io.FileOutputStream(new java.io.File(sFilesDir, file))) {
            out.write(content.getBytes(java.nio.charset.StandardCharsets.US_ASCII));
            return true;
        } catch (java.io.IOException e) {
            Log.w(TAG, "bridge request " + file + " failed: " + e);
            return false;
        }
    }

    /**
     * GSIs have no Moaan EinkService. There the vendor sepolicy still lets platform_app (and
     * system_app) set vendor_ebook_prop, so a build signed with the GSI's platform key (AOSP test
     * keys on TrebleDroid builds) can call SystemProperties.set itself; platform-signed apps are
     * also exempt from hidden-API restrictions.
     */
    private static Boolean sDirect;
    private static boolean directSetAllowed() {
        if (sDirect == null) {
            try {
                Class.forName("android.os.SystemProperties").getMethod("set", String.class, String.class);
                sDirect = !"".equals(directGet(PROP_MODE));   // readable => platform_app domain
            } catch (Throwable t) {
                sDirect = false;
            }
        }
        return sDirect;
    }

    private static String directGet(String key) {
        try {
            return (String) Class.forName("android.os.SystemProperties")
                    .getMethod("get", String.class).invoke(null, key);
        } catch (Throwable t) {
            return "";
        }
    }

    private static boolean directSet(String key, String value) {
        try {
            Class.forName("android.os.SystemProperties")
                    .getMethod("set", String.class, String.class).invoke(null, key, value);
            return true;
        } catch (Throwable t) {
            Log.w(TAG, "SystemProperties.set " + key + "=" + value + " failed: " + t);
            return false;
        }
    }

    static synchronized boolean setProperty(String key, String value) {
        for (int attempt = 0; attempt < 2; attempt++) {
            IBinder b = binder();
            if (b == null) {
                if (directSetAllowed()) return directSet(key, value);
                return bridgeAvailable() && bridgeSet(key, value);
            }
            Parcel data = Parcel.obtain();
            Parcel reply = Parcel.obtain();
            try {
                data.writeInterfaceToken(DESCRIPTOR);
                data.writeString(key);
                data.writeString(value);
                b.transact(TX_SET_PROPERTY, data, reply, 0);
                reply.readException();
                return true;
            } catch (RemoteException | RuntimeException e) {
                Log.w(TAG, "setProperty " + key + "=" + value + " failed: " + e);
                sBinder = null; // stale binder (service restart)? refetch once
            } finally {
                data.recycle();
                reply.recycle();
            }
        }
        return false;
    }

    /** When the last lookup found no "eink" service. On GSIs it never exists, and every lookup
     *  logs an SELinux denial (service_manager find), so misses are retried only every 5 min
     *  (stock could still be starting it when we first ask). */
    private static long sMissAt = -1;

    private static IBinder binder() {
        if (sBinder != null && sBinder.pingBinder()) return sBinder;
        sBinder = null;
        long now = android.os.SystemClock.elapsedRealtime();
        if (sMissAt >= 0 && now - sMissAt < 5 * 60_000L) return null;
        IBinder b = getServiceReflect();
        if (b == null && !sExemptionTried) {
            sExemptionTried = true;
            if (exemptHiddenApis()) b = getServiceReflect();
        }
        sBinder = b;
        sMissAt = b == null ? now : -1;
        if (b == null && !sMissingLogged) {   // normal on GSIs: log once, then use the direct path
            sMissingLogged = true;
            Log.i(TAG, "no eink binder service; direct property path " + (directSetAllowed() ? "available" : "NOT available"));
        }
        return b;
    }

    /** ServiceManager.getService is @UnsupportedAppUsage (greylist) on Android 11 -> usually allowed. */
    private static IBinder getServiceReflect() {
        try {
            Class<?> sm = Class.forName("android.os.ServiceManager");
            Method m = sm.getDeclaredMethod("getService", String.class);
            return (IBinder) m.invoke(null, "eink");
        } catch (Throwable t) {
            Log.w(TAG, "ServiceManager.getService reflection failed: " + t);
            return null;
        }
    }

    /**
     * Fallback: VMRuntime.setHiddenApiExemptions double-reflection trick ("meta-reflection":
     * reflect through Class.getDeclaredMethod so the caller is the boot classpath).
     * Works on Android 9-11; closed on later releases. Only used if the plain call fails.
     */
    private static boolean exemptHiddenApis() {
        try {
            Method forName = Class.class.getDeclaredMethod("forName", String.class);
            Method getDeclaredMethod = Class.class.getDeclaredMethod(
                    "getDeclaredMethod", String.class, Class[].class);
            Class<?> vmRuntime = (Class<?>) forName.invoke(null, "dalvik.system.VMRuntime");
            Method getRuntime = (Method) getDeclaredMethod.invoke(vmRuntime, "getRuntime", null);
            Method setExemptions = (Method) getDeclaredMethod.invoke(
                    vmRuntime, "setHiddenApiExemptions", new Class[]{String[].class});
            Object runtime = getRuntime.invoke(null);
            setExemptions.invoke(runtime, (Object) new String[]{"L"});
            return true;
        } catch (Throwable t) {
            Log.w(TAG, "hidden API exemption failed: " + t);
            return false;
        }
    }
}
