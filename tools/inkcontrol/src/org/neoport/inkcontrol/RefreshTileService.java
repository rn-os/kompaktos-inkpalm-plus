package org.neoport.inkcontrol;

import android.service.quicksettings.Tile;
import android.service.quicksettings.TileService;

public class RefreshTileService extends TileService {
    @Override public void onStartListening() {
        Tile t = getQsTile();
        if (t == null) return;
        t.setState(Tile.STATE_INACTIVE);
        t.setLabel("Full refresh");
        t.setIcon(TextIcon.of("REFRESH"));
        t.updateTile();
    }

    @Override public void onClick() {
        Actions.fullRefresh(this);
    }
}
