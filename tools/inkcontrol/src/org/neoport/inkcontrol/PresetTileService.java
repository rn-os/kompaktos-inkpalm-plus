package org.neoport.inkcontrol;

import android.service.quicksettings.Tile;
import android.service.quicksettings.TileService;

/** One tile per KompaktOS preset (same names): a tap selects it as the default and flashes. */
public abstract class PresetTileService extends TileService {
    abstract int index();

    @Override public void onStartListening() { render(); }

    @Override public void onClick() {
        Prefs p = new Prefs(this);
        int mode = Presets.MODES[index()];
        if (p.defaultMode() != mode) {
            p.setDefaultMode(mode);
            Actions.applyModeAndFlash(this, mode);
        }
        render();
    }

    private void render() {
        Tile t = getQsTile();
        if (t == null) return;
        t.setLabel(Presets.LABELS[index()]);
        t.setIcon(TextIcon.of(Presets.ICON_TEXT[index()]));
        t.setSubtitle("E-ink");
        t.setState(new Prefs(this).defaultMode() == Presets.MODES[index()]
                ? Tile.STATE_ACTIVE : Tile.STATE_INACTIVE);
        t.updateTile();
    }

    public static class Fast extends PresetTileService { int index() { return 0; } }
    public static class Soft extends PresetTileService { int index() { return 1; } }
    public static class Dither extends PresetTileService { int index() { return 2; } }
    public static class Text extends PresetTileService { int index() { return 3; } }
    public static class Quality extends PresetTileService { int index() { return 4; } }
    public static class Auto extends PresetTileService { int index() { return 5; } }
}
