package org.neoport.inkcontrol;

import android.service.quicksettings.Tile;
import android.service.quicksettings.TileService;

/** Quick Settings tile: tap opens the frontlight panel (on/off, brightness, warmth). */
public class LightTileService extends TileService {
    @Override public void onStartListening() { refresh(); }

    @Override public void onClick() {
        if (!Light.supported()) return;
        android.content.Intent i = new android.content.Intent(this, FrontlightPanel.class)
                .addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK);
        startActivityAndCollapse(i);
    }

    private void refresh() {
        Tile t = getQsTile();
        if (t == null) return;
        boolean ok = Light.supported();
        t.setState(!ok ? Tile.STATE_UNAVAILABLE : Light.isOn(this) ? Tile.STATE_ACTIVE : Tile.STATE_INACTIVE);
        t.setLabel("Frontlight");
        t.setIcon(TextIcon.of("LIGHT"));
        t.updateTile();
    }
}
