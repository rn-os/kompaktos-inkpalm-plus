# InkPalm Plus product layer (Make half): files that must land at the paths bake.sh proved on
# the device, which Soong cannot install to:
#   /system/phh/inkpalm/lib64/<stock lib>.so   stock Android 11 libs from YOUR backup (blobs/)
#   /system/phh/inkpalm/<script>.sh            init services (vendor-fix/, unmodified)
# Plain file copies (class ETC), so make does not treat the foreign ELFs as libraries.
# Modes/owners/labels: fs_config would give these 0644 root:root; the scripts need 0755 and
# phhsu_exec, the libs vendor_file. sepolicy/file_contexts covers the labels; build.sh's
# post-build step checks all of it on system.img and fixes it with debugfs (bake.sh's method).
# UNVERIFIED: never built.

LOCAL_PATH := $(call my-dir)

# vendor/inkpalm only exists in trees prepared by build-layer/build.sh, so failing hard on
# missing blobs here cannot break anyone else's build.
INKPALM_STOCK_LIBS := libskia libdng_sdk libft2 libandroidicu libicuuc libicui18n

$(foreach lib,$(INKPALM_STOCK_LIBS),\
  $(if $(wildcard $(LOCAL_PATH)/blobs/$(lib).so),,\
    $(error vendor/inkpalm/blobs/$(lib).so missing: run build-layer/extract-blobs.sh and copy blobs/ to the server)))

define inkpalm-stock-lib
include $$(CLEAR_VARS)
LOCAL_MODULE := inkpalm_stock_$(1)
LOCAL_MODULE_CLASS := ETC
LOCAL_MODULE_STEM := $(1).so
LOCAL_SRC_FILES := blobs/$(1).so
LOCAL_MODULE_PATH := $$(TARGET_OUT)/phh/inkpalm/lib64
LOCAL_MODULE_TAGS := optional
include $$(BUILD_PREBUILT)
endef
$(foreach lib,$(INKPALM_STOCK_LIBS),$(eval $(call inkpalm-stock-lib,$(lib))))

INKPALM_SCRIPTS := inkpalm-vfix eink-bridge eink-apply inkpalm-defaults inkpalm-poweroff

define inkpalm-script
include $$(CLEAR_VARS)
LOCAL_MODULE := inkpalm_script_$(subst -,_,$(1))
LOCAL_MODULE_CLASS := ETC
LOCAL_MODULE_STEM := $(1).sh
LOCAL_SRC_FILES := vendor-fix/$(1).sh
LOCAL_MODULE_PATH := $$(TARGET_OUT)/phh/inkpalm
LOCAL_MODULE_TAGS := optional
include $$(BUILD_PREBUILT)
endef
$(foreach s,$(INKPALM_SCRIPTS),$(eval $(call inkpalm-script,$(s))))
