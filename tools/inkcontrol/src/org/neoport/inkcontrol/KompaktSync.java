package org.neoport.inkcontrol;

import android.util.Xml;

import org.xmlpull.v1.XmlPullParser;

import java.io.File;
import java.io.FileInputStream;
import java.util.HashMap;
import java.util.Map;

/**
 * Read-only view of KompaktOS' own e-ink config. KompaktService keeps it in its PRIVATE
 * SharedPreferences "kompakt" (not Settings), so an unprivileged app cannot read it. If the image's
 * root helper copies /data/data/com.kompakt.service/shared_prefs/kompakt.xml to
 * files/kompakt_prefs.xml (see README, "needs bridge change"), this class parses it:
 *   eink_mode = master preset, per_app = per-app switch,
 *   app_mode_PKG = preset, invert_PKG = true.
 */
final class KompaktSync {
    static final String FILE = "kompakt_prefs.xml";

    final String master;            // preset key or null
    final boolean perApp;           // KompaktOS default true
    final Map<String, String> appMode = new HashMap<>();
    final Map<String, Boolean> invert = new HashMap<>();

    private KompaktSync(String master, boolean perApp) { this.master = master; this.perApp = perApp; }

    private static File sFile;
    private static long sStamp = -1;
    private static KompaktSync sCached;

    /** Null if the copy does not exist or cannot be parsed. Cheap: cached by mtime. */
    static synchronized KompaktSync get(File filesDir) {
        File f = new File(filesDir, FILE);
        if (!f.isFile()) { sCached = null; sStamp = -1; return null; }
        long stamp = f.lastModified() ^ f.length();
        if (f.equals(sFile) && stamp == sStamp) return sCached;
        sFile = f; sStamp = stamp;
        sCached = parse(f);
        return sCached;
    }

    private static KompaktSync parse(File f) {
        try (FileInputStream in = new FileInputStream(f)) {
            XmlPullParser p = Xml.newPullParser();
            p.setInput(in, "UTF-8");
            String master = null;
            boolean perApp = true;
            Map<String, String> modes = new HashMap<>();
            Map<String, Boolean> inv = new HashMap<>();
            for (int ev = p.getEventType(); ev != XmlPullParser.END_DOCUMENT; ev = p.next()) {
                if (ev != XmlPullParser.START_TAG) continue;
                String tag = p.getName(), name = p.getAttributeValue(null, "name");
                if (name == null) continue;
                if ("string".equals(tag)) {
                    String v = p.nextText();
                    if (name.equals("eink_mode")) master = v;
                    else if (name.startsWith("app_mode_")) modes.put(name.substring(9), v);
                } else if ("boolean".equals(tag)) {
                    boolean v = "true".equals(p.getAttributeValue(null, "value"));
                    if (name.equals("per_app")) perApp = v;
                    else if (name.startsWith("invert_")) inv.put(name.substring(7), v);
                }
            }
            KompaktSync k = new KompaktSync(master, perApp);
            k.appMode.putAll(modes);
            k.invert.putAll(inv);
            return k;
        } catch (Throwable t) {
            android.util.Log.w("InkControl", "kompakt prefs parse failed: " + t);
            return null;
        }
    }
}
