# InkPalm Plus product layer on top of KompaktOS (vendor/kompakt). What gsi/vendor-fix/bake.sh
# patched into a finished system.img, done by the build instead:
#   display fix   stock A11 libs + stub libheif overlaid on /vendor/lib64 by init (inkpalm-vfix.rc)
#   touch         fts_ts.idc, ORIENTATION_270
#   navigation    gesture nav default (product overlay config; one capacitive button only)
#   first boot    inkpalm-defaults.sh (wake-on-plug off, density 312; once, marker-guarded)
#   boot anim     KompaktOS animation rescaled to 720x1440 (blobs/bootanimation.zip)
#   e-ink/light   InkControl as a privileged platform-signed app + the transitional root bridge
#
# build.sh appends `$(call inherit-product, vendor/inkpalm/inkpalm.mk)` to the end of the
# generated device/phh/treble/lineage_arm64_bvN4.mk, i.e. after lineage.mk has inherited
# vendor/kompakt/kompakt.mk. Plain variables set here (TARGET_BOOTANIMATION) therefore win over
# kompakt.mk; PRODUCT_COPY_FILES go the other way (first one wins), which is why build.sh checks
# every file below in the finished system.img.
# Signing is NOT set here: keys.mk in vendor/lineage-priv/keys is the only place (signing.md).
# UNVERIFIED: never built.

# Display fix: stock blobs + scripts (Android.mk), stub libheif + rc (Android.bp).
PRODUCT_PACKAGES += \
    inkpalm_stock_libskia \
    inkpalm_stock_libdng_sdk \
    inkpalm_stock_libft2 \
    inkpalm_stock_libandroidicu \
    inkpalm_stock_libicuuc \
    inkpalm_stock_libicui18n \
    libheif_inkpalm_stub \
    inkpalm-vfix.rc \
    inkpalm_script_inkpalm_vfix \
    inkpalm_script_inkpalm_defaults

# E-ink bridge: TRANSITIONAL. InkControl is platform-signed in this build and sets sys.eink.*
# itself; the bridge remains for the frontlight (/proc/aw99703*) and the sleep image.
# TODO(sepolicy): allow platform_app to set vendor_ebook_prop (stock vendor policy already does)
# and to write the aw99703 proc nodes (see sepolicy/file_contexts), then drop these two.
PRODUCT_PACKAGES += \
    inkpalm_script_eink_bridge \
    inkpalm_script_eink_apply

# InkControl, privileged, platform certificate (Android.bp).
PRODUCT_PACKAGES += InkControl

# Touch panel orientation.
PRODUCT_COPY_FILES += \
    vendor/inkpalm/vendor-fix/fts_ts.idc:$(TARGET_COPY_OUT_SYSTEM)/usr/idc/fts_ts.idc

# Gesture navigation by default; still switchable in Settings.
PRODUCT_COPY_FILES += \
    vendor/inkpalm/vendor-fix/product-overlay-config.xml:$(TARGET_COPY_OUT_PRODUCT)/overlay/config/config.xml

# Boot animation, 720x1440 (extract-blobs.sh --kompakt-system/--bootanim; build.sh copies it in).
# Overrides kompakt.mk's vendor/kompakt/bootanimation/bootanimation.zip, which is gitignored
# upstream and not produced by a clean upstream checkout.
TARGET_BOOTANIMATION := vendor/inkpalm/bootanimation/bootanimation.zip
TARGET_BOOTANIMATION_HALF_RES := false
