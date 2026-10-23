package org.neoport.inkcontrol;

import android.service.quicksettings.Tile;
import android.service.quicksettings.TileService;

/** Cycles the global default mode through Modes.CYCLE and applies it immediately. */
public class ModeTileService extends TileService {
    @Override public void onStartListening() { refresh(); }

    @Override public void onClick() {
        Prefs p = new Prefs(this);
        int cur = p.defaultMode();
        int next = Presets.MODES[0];
        for (int i = 0; i < Modes.CYCLE.length; i++) {
            if (Modes.CYCLE[i] == cur) { next = Modes.CYCLE[(i + 1) % Modes.CYCLE.length]; break; }
        }
        p.setDefaultMode(next);
        Actions.applyModeAndFlash(this, next);
        refresh();
    }

    /** Current preset as one short word for the icon (falls back to the mode number). */
    private static String iconWord(int mode) {
        for (int i = 0; i < Presets.MODES.length; i++) {
            if (Presets.MODES[i] == mode) return Presets.ICON_TEXT[i].replace("\n", " ").replace("FAST ", "");
        }
        return String.valueOf(mode);
    }

    private void refresh() {
        Tile t = getQsTile();
        if (t == null) return;
        t.setLabel("E-ink mode");
        int mode = new Prefs(this).defaultMode();
        t.setSubtitle(Modes.shortName(mode));
        t.setIcon(TextIcon.of("MODE\n" + iconWord(mode)));
        t.setState(Tile.STATE_ACTIVE);
        t.updateTile();
    }
}
