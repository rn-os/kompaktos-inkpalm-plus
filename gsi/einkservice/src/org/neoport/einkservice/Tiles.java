package org.neoport.einkservice;

import android.graphics.drawable.Icon;
import android.service.quicksettings.Tile;
import android.service.quicksettings.TileService;

/** Quick Settings tiles (Kompakt: Tiles.kt). Two tiles are enough to start; per-mode tiles are a loop away. */
public class Tiles {
    private Tiles() {}

    /** Tap cycles the global default mode. */
    public static class ModeTile extends TileService {
        @Override public void onStartListening() { render(); }
        @Override public void onClick() {
            EinkController c = EinkController.get(this);
            String next = EinkModes.next(c.prefs.globalMode());
            c.setGlobalMode(next);
            render();
            c.fullRefresh();   // a mode change leaves the previous mode's ghosting behind
        }
        private void render() {
            Tile t = getQsTile();
            if (t == null) return;
            EinkController c = EinkController.get(this);
            t.setLabel("E-ink mode");
            t.setSubtitle(EinkModes.get(c.prefs.globalMode()).label);
            t.setIcon(Icon.createWithResource(this, R.drawable.ic_eink));
            t.setState(Tile.STATE_ACTIVE);
            t.updateTile();
        }
    }

    public static class RefreshTile extends TileService {
        @Override public void onStartListening() {
            Tile t = getQsTile();
            if (t == null) return;
            t.setLabel("Refresh screen");
            t.setIcon(Icon.createWithResource(this, R.drawable.ic_eink));
            t.setState(Tile.STATE_INACTIVE);
            t.updateTile();
        }
        @Override public void onClick() { EinkController.get(this).fullRefresh(); }
    }
}
