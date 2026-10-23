package org.neoport.inkcontrol;

import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.Rect;
import android.graphics.Typeface;
import android.graphics.drawable.Icon;

/**
 * Quick Settings icons that are the tile's name. KompaktOS shows QS tiles icon-only, so a
 * generic glyph can't tell the e-ink presets apart; this renders the word itself (bold,
 * condensed, auto-fitted, up to two lines) as a white mask that SystemUI tints like any icon.
 */
final class TextIcon {
    private static final int SIZE = 96;

    private TextIcon() {}

    /** Use "\n" to force a line break; otherwise one line, shrunk to fit. */
    static Icon of(String text) {
        Bitmap b = Bitmap.createBitmap(SIZE, SIZE, Bitmap.Config.ARGB_8888);
        Canvas c = new Canvas(b);
        Paint p = new Paint(Paint.ANTI_ALIAS_FLAG);
        p.setColor(0xffffffff);
        p.setTypeface(Typeface.create("sans-serif-condensed", Typeface.BOLD));
        p.setTextAlign(Paint.Align.CENTER);
        String[] lines = text.split("\n");
        float maxW = SIZE - 4, maxLineH = (SIZE - 4) / (float) lines.length;
        float size = maxLineH;
        for (String l : lines) {
            p.setTextSize(100);
            float w = p.measureText(l);
            size = Math.min(size, 100 * maxW / Math.max(1, w));
        }
        p.setTextSize(size);
        Paint.FontMetrics fm = p.getFontMetrics();
        float lineH = fm.descent - fm.ascent;
        float top = (SIZE - lineH * lines.length) / 2f - fm.ascent;
        for (int i = 0; i < lines.length; i++) c.drawText(lines[i], SIZE / 2f, top + i * lineH, p);
        return Icon.createWithBitmap(b);
    }
}
