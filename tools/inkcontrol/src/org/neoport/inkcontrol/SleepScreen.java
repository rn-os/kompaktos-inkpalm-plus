package org.neoport.inkcontrol;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Canvas;
import android.graphics.ColorMatrix;
import android.graphics.ColorMatrixColorFilter;
import android.graphics.Paint;
import android.graphics.Rect;
import android.net.Uri;
import android.util.DisplayMetrics;
import android.view.WindowManager;

import java.io.FileOutputStream;
import java.io.InputStream;

/**
 * Custom sleep screen on GSIs. The vendor HWC draws /data/misc/standby.png when the screen
 * turns off (see docs/sleep-screen.md); apps can't write there, so the picked image is
 * centre-cropped to the panel size, made grayscale, saved as files/standby.png and applied by
 * the root bridge (standby.req, gsi/vendor-fix/eink-apply.sh).
 */
final class SleepScreen {
    private SleepScreen() {}

    static boolean supported() {
        return Eink.bridgeAvailable();
    }

    /** Returns null on success, else an error message. Runs on the caller's thread. */
    static String apply(Context c, Uri uri) {
        try {
            DisplayMetrics dm = new DisplayMetrics();
            ((WindowManager) c.getSystemService(Context.WINDOW_SERVICE)).getDefaultDisplay().getRealMetrics(dm);
            int w = Math.min(dm.widthPixels, dm.heightPixels), h = Math.max(dm.widthPixels, dm.heightPixels);

            BitmapFactory.Options o = new BitmapFactory.Options();
            o.inJustDecodeBounds = true;
            try (InputStream in = c.getContentResolver().openInputStream(uri)) { BitmapFactory.decodeStream(in, null, o); }
            if (o.outWidth <= 0) return "not an image";
            o.inJustDecodeBounds = false;
            o.inSampleSize = 1;
            while (o.outWidth / (o.inSampleSize * 2) >= w && o.outHeight / (o.inSampleSize * 2) >= h) o.inSampleSize *= 2;
            Bitmap src;
            try (InputStream in = c.getContentResolver().openInputStream(uri)) { src = BitmapFactory.decodeStream(in, null, o); }
            if (src == null) return "could not decode image";

            // Centre-crop to the panel's aspect ratio, scale to fill, grayscale for e-ink.
            float scale = Math.max((float) w / src.getWidth(), (float) h / src.getHeight());
            int cw = Math.round(w / scale), ch = Math.round(h / scale);
            Rect from = new Rect((src.getWidth() - cw) / 2, (src.getHeight() - ch) / 2,
                    (src.getWidth() + cw) / 2, (src.getHeight() + ch) / 2);
            Bitmap out = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888);
            Paint p = new Paint(Paint.FILTER_BITMAP_FLAG);
            ColorMatrix gray = new ColorMatrix();
            gray.setSaturation(0);
            p.setColorFilter(new ColorMatrixColorFilter(gray));
            new Canvas(out).drawBitmap(src, from, new Rect(0, 0, w, h), p);

            java.io.File f = new java.io.File(c.getFilesDir(), "standby.png");
            try (FileOutputStream fo = new FileOutputStream(f)) { out.compress(Bitmap.CompressFormat.PNG, 100, fo); }
            if (f.length() > 10L * 1024 * 1024) return "image too large after conversion";
            return Eink.bridgeWrite("standby.req", "apply=1\n") ? null : "bridge not available";
        } catch (Exception e) {
            return e.toString();
        }
    }

    static boolean reset() {
        return Eink.bridgeWrite("standby.req", "reset=1\n");
    }
}
