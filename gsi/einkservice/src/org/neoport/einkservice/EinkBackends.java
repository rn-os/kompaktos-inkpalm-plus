package org.neoport.einkservice;

/** Picks the panel backend. Rockchip first (the target), Kompakt sysfs if its nodes exist. */
final class EinkBackends {
    private EinkBackends() {}

    static EinkBackend select() {
        EinkBackend kompakt = new KompaktSysfsBackend();
        if (kompakt.available()) return kompakt;
        return new RkEinkBackend();
    }
}
