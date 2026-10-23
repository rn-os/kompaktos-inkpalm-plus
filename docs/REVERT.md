# Getting back to stock Moaan firmware

Stock: `MAS_EPD305_L81B804_T44_V09`, Android 11, **slot B** (active). Slot A holds an older
stock build (Jan 2024). Bootloader unlocked (fastbootd reports `unlocked: yes`).

## Route 1 — DSU test boots (used first; stock is never written)
Generic images are first tried through Android's **Dynamic System Updates**: the image is
installed as a file inside userdata with its *own* separate data, and booted on request.
Slot B's boot/vbmeta/super partitions and the stock userdata are not modified.

Back to stock from a DSU boot, any of:
1. **Reboot.** A DSU boot is one-shot unless made persistent; the next normal boot is stock.
2. If the DSU image hangs or bootloops: **hold power 10–15 s**; the following boot is stock.
3. In stock, remove it: the "Dynamic System" notification → *Discard*, or
   Settings → System → Developer options → DSU loader, or wait for it to be discarded.

### Persistent DSU (enabled 2026-10-23 for daily use of LineageOS 23.2 / Android 16)
`gsi_tool enable` makes the DSU image boot every time, so a reboot no longer returns to stock.
Back to stock, any of:
1. From the running GSI: `adb root && adb shell gsi_tool disable && adb reboot`
   (`gsi_tool enable -s` would make it one-shot again; `gsi_tool wipe` deletes it entirely).
2. If the GSI won't boot: hold power 10–15 s; after a failed DSU boot Android falls back to the
   normal system. Or from fastbootd: `adb reboot fastboot` (or bootloader menu) then
   `fastboot gsi disable` / `fastboot gsi wipe`.
3. Full restore from images (last resort): ~/InkPalm-Backup/partitions-full (super, boot_b,
   vbmeta_b, dtbo_b, ... verified 2026-10-23). Don't restore `security` without a reason.

## Route 2 — slot switching (only if we later flash for real)
Rule: **never write any `_b` partition.** Every flash names `_a` explicitly; a bare
`fastboot flash system` would hit the active slot (b).
- Back to stock: `fastboot set_active b` (works from fastbootd and from U-Boot fastboot),
  then `fastboot -w` (userdata is shared between slots; the generic image will have
  re-formatted it), reboot, then restore files from `~/InkPalm-Backup` (see its README).
- Space note: slot B uses 2.27 GB of the 5.37 GB super; a 2.55 GB generic system
  does not fit in slot A next to slot A's 924 MB odm — another reason DSU comes first.

## What a slot-B wipe would lose
Restored from `~/InkPalm-Backup`: all of /sdcard (incl. Android/data), 38 user APKs,
inkOS / PipePipe / NewPipe / AntennaPod exports, screenshots of the launcher setup.
Not restorable: app-internal data under /data/data (logins, app databases without an
export). Not backed up as raw images: boot, vbmeta, dtbo, super (Moaan's loader blocks
reads past 32 MiB; Maskrom download failed on the Mac).
