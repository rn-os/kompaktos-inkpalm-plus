package org.neoport.inkcontrol;

import android.app.Activity;
import android.os.Bundle;
import android.view.Gravity;
import android.view.Window;
import android.widget.Button;
import android.widget.CheckBox;
import android.widget.LinearLayout;
import android.widget.SeekBar;
import android.widget.Switch;
import android.widget.TextView;

/**
 * Boox-style frontlight panel (opened from the "Frontlight" Quick Settings tile): independent
 * Cold and Warm lights, each with an on/off switch, -/+ fine steps and a slider; optional link
 * to the system brightness slider; optional edge-swipe control. Values apply on release / tap,
 * not continuously, so the e-ink panel isn't redrawn on every slider tick.
 */
public class FrontlightPanel extends Activity {
    private static final int STEP = 5;
    private float dp;

    @Override protected void onCreate(Bundle b) {
        super.onCreate(b);
        requestWindowFeature(Window.FEATURE_NO_TITLE);
        dp = getResources().getDisplayMetrics().density;
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        int pad = px(20);
        root.setPadding(pad, pad, pad, pad);
        root.setBackgroundColor(0xffffffff);

        root.addView(label("Frontlight", 20));
        root.addView(channel("Cold light", Light.COLD));
        root.addView(channel("Warm light", Light.WARM));

        CheckBox follow = check("Scale both with the system brightness slider", Light.followSystem(this));
        follow.setOnCheckedChangeListener((v, c) -> Light.setFollowSystem(this, c));
        root.addView(follow);
        CheckBox edge = check("Edge swipe: left edge = cold, right edge = warm", Light.edgeSwipe(this));
        edge.setOnCheckedChangeListener((v, c) -> {
            Light.setEdgeSwipe(this, c);
            AppWatcherService.refreshEdgeStrips();
        });
        root.addView(edge);

        setContentView(root);
        getWindow().setGravity(Gravity.TOP);
        getWindow().setLayout(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT);
    }

    private LinearLayout channel(String name, int ch) {
        LinearLayout box = new LinearLayout(this);
        box.setOrientation(LinearLayout.VERTICAL);
        box.setPadding(0, px(10), 0, 0);

        LinearLayout head = new LinearLayout(this);
        head.setGravity(Gravity.CENTER_VERTICAL);
        TextView title = label(name + "   " + Light.level(this, ch) + "%", 16);
        title.setLayoutParams(new LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1));
        head.addView(title);
        Switch on = new Switch(this);
        on.setChecked(Light.isOn(this, ch));
        on.setOnCheckedChangeListener((v, c) -> Light.setOn(this, ch, c));
        head.addView(on);
        box.addView(head);

        LinearLayout row = new LinearLayout(this);
        row.setGravity(Gravity.CENTER_VERTICAL);
        SeekBar bar = new SeekBar(this);
        bar.setMax(100);
        bar.setProgress(Light.level(this, ch));
        bar.setLayoutParams(new LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1));
        Runnable show = () -> title.setText(name + "   " + Light.level(this, ch) + "%");
        Button minus = stepButton("−", () -> { Light.setLevel(this, ch, Light.level(this, ch) - STEP); bar.setProgress(Light.level(this, ch)); show.run(); });
        Button plus = stepButton("+", () -> { Light.setLevel(this, ch, Light.level(this, ch) + STEP); bar.setProgress(Light.level(this, ch)); show.run(); });
        bar.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener() {
            @Override public void onProgressChanged(SeekBar s, int p, boolean user) {
                if (user) title.setText(name + "   " + p + "%");
            }
            @Override public void onStartTrackingTouch(SeekBar s) {}
            @Override public void onStopTrackingTouch(SeekBar s) { Light.setLevel(FrontlightPanel.this, ch, s.getProgress()); }
        });
        row.addView(minus);
        row.addView(bar);
        row.addView(plus);
        box.addView(row);
        return box;
    }

    private Button stepButton(String t, Runnable r) {
        Button b = new Button(this);
        b.setText(t);
        b.setTextSize(20);
        b.setMinWidth(px(48));
        b.setOnClickListener(v -> r.run());
        return b;
    }

    private CheckBox check(String t, boolean checked) {
        CheckBox c = new CheckBox(this);
        c.setText(t);
        c.setTextColor(0xff000000);
        c.setChecked(checked);
        c.setPadding(0, px(6), 0, px(6));
        return c;
    }

    private TextView label(String s, int sp) {
        TextView t = new TextView(this);
        t.setText(s);
        t.setTextSize(sp);
        t.setTextColor(0xff000000);
        return t;
    }

    private int px(int v) { return Math.round(v * dp); }
}
