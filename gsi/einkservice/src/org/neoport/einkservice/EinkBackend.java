package org.neoport.einkservice;

/**
 * The panel-specific half. Everything above this interface (per-app modes, tiles, unlock refresh,
 * screen-off handling) is panel independent and ported from KompaktService.
 *
 * Implementations: {@link RkEinkBackend} (Rockchip ebc via sys.eink.* props, the InkPalm) and
 * {@link KompaktSysfsBackend} (Mudita Kompakt, /sys/einkinfo/*), kept so the same app can be
 * built for both. {@link EinkBackends#select()} picks one at runtime.
 */
interface EinkBackend {
    String name();

    /** True when this backend's control path exists on this device (cheap, no side effects). */
    boolean available();

    /** Panel setup at boot: write the defaults the stock firmware used to write implicitly. */
    void applyBootDefaults(EinkPrefs prefs);

    /** Apply one preset. Must be idempotent; may be called several times for the same mode. */
    void applyMode(EinkModes.Mode mode, EinkPrefs prefs);

    /** Drive a real full-panel refresh (de-ghost). Returns false if the backend cannot. */
    boolean fullRefresh();

    /** Display went non-interactive (true) or interactive again (false). */
    void onScreenState(boolean interactive, EinkPrefs prefs);
}
