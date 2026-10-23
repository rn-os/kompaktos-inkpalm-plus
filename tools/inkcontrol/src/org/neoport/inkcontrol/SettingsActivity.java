package org.neoport.inkcontrol;

import android.app.Activity;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.content.pm.ResolveInfo;
import android.os.Bundle;
import android.provider.Settings;
import android.view.View;
import android.view.ViewGroup;
import android.widget.AdapterView;
import android.widget.ArrayAdapter;
import android.widget.Button;
import android.widget.CheckBox;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.Spinner;
import android.widget.TextView;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

/** Plain-View, animation-free settings screen: status, global mode, refresh, per-app rows. */
public class SettingsActivity extends Activity {
    private Prefs prefs;
    private TextView status;
    private float dp;

    @Override protected void onCreate(Bundle b) {
        super.onCreate(b);
        prefs = new Prefs(this);
        dp = getResources().getDisplayMetrics().density;

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        int pad = px(16);
        root.setPadding(pad, pad, pad, pad);

        root.addView(text("InkControl", 24));
        status = text("", 14);
        root.addView(status);

        root.addView(text("Global default mode", 18));
        int[] noDefault = new int[Modes.VALUES.length - 1];
        System.arraycopy(Modes.VALUES, 1, noDefault, 0, noDefault.length);
        String[] noDefaultLabels = new String[Modes.LABELS.length - 1];
        System.arraycopy(Modes.LABELS, 1, noDefaultLabels, 0, noDefaultLabels.length);
        int globalSel = Math.max(0, Modes.indexOf(prefs.defaultMode()) - 1);
        Spinner global = spinner(noDefaultLabels, globalSel);
        global.setOnItemSelectedListener(new Picked(globalSel) { void picked(int i) {
            prefs.setDefaultMode(noDefault[i]);
            Actions.applyMode(noDefault[i], true);
        }});
        root.addView(global);

        Button refresh = new Button(this);
        refresh.setText("Full refresh now");
        refresh.setOnClickListener(v -> Actions.fullRefresh(this));
        root.addView(refresh);


        CheckBox follow = new CheckBox(this);
        follow.setText("Follow KompaktOS per-app config (when synced)");
        follow.setChecked(prefs.followKompakt());
        follow.setOnCheckedChangeListener((v, on) -> prefs.setFollowKompakt(on));
        root.addView(follow);
        CheckBox flash = new CheckBox(this);
        flash.setText("Full flash when KompaktOS refreshes (tile / long-press Home)");
        flash.setChecked(prefs.flashOnKompaktRefresh());
        flash.setOnCheckedChangeListener((v, on) -> prefs.setFlashOnKompaktRefresh(on));
        root.addView(flash);

        if (Light.supported()) addLightSection(root);
        if (SleepScreen.supported()) addSleepSection(root);
        if (AutoOff.supported()) addAutoOffSection(root);

        root.addView(text("Per-app settings", 18));
        for (ResolveInfo ri : launchableApps()) root.addView(appRow(ri));

        ScrollView sv = new ScrollView(this);
        sv.addView(root);
        setContentView(sv);
    }

    @Override protected void onResume() {
        super.onResume();
        String enabled = Settings.Secure.getString(getContentResolver(),
                Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES);
        boolean a11y = enabled != null && enabled.contains(getPackageName() + "/");
        boolean secure = checkSelfPermission("android.permission.WRITE_SECURE_SETTINGS")
                == PackageManager.PERMISSION_GRANTED;
        String backend = Eink.backend();
        status.setText("Per-app service: " + (a11y ? "ON" : "off (enable in Accessibility)")
                + "\nInvert permission: " + (secure ? "granted" : "not granted (adb pm grant)")
                + "\nE-ink control: " + (backend.equals("binder") ? "Moaan eink service"
                        : backend.equals("direct") ? "direct (platform-signed, GSI)"
                        : backend.equals("bridge") ? "InkPalm bridge (GSI)" : "NOT available")
                + "\nKompaktOS config: " + (KompaktSync.get(getFilesDir()) != null
                        ? "synced (per-app modes follow KompaktOS)"
                        : "not synced (using InkControl's own per-app list)"));
    }

    private static final int PICK_SLEEP_IMAGE = 41;

    /** Sleep screen: pick an image (shown by the vendor HWC when the screen turns off). */
    private void addSleepSection(LinearLayout root) {
        root.addView(text("Sleep screen", 18));
        Button pick = new Button(this);
        pick.setText("Choose image\u2026");
        pick.setOnClickListener(v -> startActivityForResult(
                new android.content.Intent(android.content.Intent.ACTION_OPEN_DOCUMENT)
                        .addCategory(android.content.Intent.CATEGORY_OPENABLE).setType("image/*"),
                PICK_SLEEP_IMAGE));
        root.addView(pick);
        Button reset = new Button(this);
        reset.setText("Reset to default");
        reset.setOnClickListener(v -> toast(SleepScreen.reset() ? "Sleep screen reset" : "Bridge not available"));
        root.addView(reset);
    }

    /** Auto power-off: shut down after N hours asleep on battery (AutoOff). */
    private void addAutoOffSection(LinearLayout root) {
        root.addView(text("Auto power-off", 18));
        int sel = 0;
        for (int i = 0; i < AutoOff.HOURS.length; i++) if (AutoOff.HOURS[i] == AutoOff.hours(this)) sel = i;
        Spinner s = spinner(AutoOff.LABELS, sel);
        s.setOnItemSelectedListener(new Picked(sel) { void picked(int i) {
            AutoOff.setHours(SettingsActivity.this, AutoOff.HOURS[i]);
        }});
        root.addView(s);
    }

    @Override protected void onActivityResult(int req, int res, android.content.Intent data) {
        super.onActivityResult(req, res, data);
        if (req != PICK_SLEEP_IMAGE || res != RESULT_OK || data == null || data.getData() == null) return;
        android.net.Uri uri = data.getData();
        Actions.post(() -> {
            String err = SleepScreen.apply(this, uri);
            runOnUiThread(() -> toast(err == null ? "Sleep screen set" : "Sleep screen failed: " + err));
        });
    }

    private void toast(String s) { android.widget.Toast.makeText(this, s, android.widget.Toast.LENGTH_LONG).show(); }

    /** Frontlight: the Boox-style panel (also on the "Frontlight" Quick Settings tile). */
    private void addLightSection(LinearLayout root) {
        root.addView(text("Frontlight", 18));
        Button open = new Button(this);
        open.setText("Frontlight settings (cold / warm)\u2026");
        open.setOnClickListener(v -> startActivity(new android.content.Intent(this, FrontlightPanel.class)));
        root.addView(open);
    }

    private View appRow(ResolveInfo ri) {
        String pkg = ri.activityInfo.packageName;
        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.VERTICAL);
        row.setPadding(0, px(10), 0, px(10));
        row.addView(text(ri.loadLabel(getPackageManager()) + "  (" + pkg + ")", 15));
        int sel = Modes.indexOf(prefs.appMode(pkg));
        Spinner s = spinner(Modes.LABELS, sel);
        s.setOnItemSelectedListener(new Picked(sel) { void picked(int i) {
            prefs.setAppMode(pkg, Modes.VALUES[i]);
        }});
        row.addView(s);
        CheckBox inv = new CheckBox(this);
        inv.setText("Invert colours in this app");
        inv.setChecked(prefs.appInvert(pkg));
        inv.setOnCheckedChangeListener((v, on) -> prefs.setAppInvert(pkg, on));
        row.addView(inv);
        return row;
    }

    private List<ResolveInfo> launchableApps() {
        Intent i = new Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER);
        List<ResolveInfo> l = new ArrayList<>(getPackageManager().queryIntentActivities(i, 0));
        PackageManager pm = getPackageManager();
        Collections.sort(l, (x, y) -> x.loadLabel(pm).toString()
                .compareToIgnoreCase(y.loadLabel(pm).toString()));
        // One row per package even if it has several launcher activities.
        List<ResolveInfo> out = new ArrayList<>();
        List<String> seen = new ArrayList<>();
        for (ResolveInfo r : l) {
            String p = r.activityInfo.packageName;
            if (p.equals(getPackageName()) || seen.contains(p)) continue;
            seen.add(p);
            out.add(r);
        }
        return out;
    }

    private Spinner spinner(String[] labels, int selected) {
        Spinner s = new Spinner(this, Spinner.MODE_DIALOG);
        ArrayAdapter<String> a = new ArrayAdapter<>(this,
                android.R.layout.simple_spinner_item, labels);
        a.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item);
        s.setAdapter(a);
        s.setSelection(selected, false);
        return s;
    }

    private TextView text(CharSequence t, int sp) {
        TextView v = new TextView(this);
        v.setText(t);
        v.setTextSize(sp);
        v.setTextColor(0xff000000);
        v.setPadding(0, px(6), 0, px(6));
        v.setLayoutParams(new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        return v;
    }

    private int px(int v) { return Math.round(v * dp); }

    /** Only reacts to real changes (Spinner also reports the initial selection on layout). */
    private abstract static class Picked implements AdapterView.OnItemSelectedListener {
        private int last;
        Picked(int initial) { last = initial; }
        abstract void picked(int position);
        @Override public void onItemSelected(AdapterView<?> p, View v, int pos, long id) {
            if (pos == last) return;
            last = pos;
            picked(pos);
        }
        @Override public void onNothingSelected(AdapterView<?> p) {}
    }
}
