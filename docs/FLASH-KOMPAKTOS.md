# Flashing KompaktOS (Vanilla) to the InkPalm Plus

Image: `~/InkPalm-Images/kompaktos/flash/super-kompaktos-vanilla.img` (built by
`tools/build_super.py` from the verified stock super backup + KompaktOS 1.2 Global Vanilla
system baked with `gsi/vendor-fix/bake.sh`).

Layout (slot B, the active slot): `system_b` = KompaktOS (3.195 GB), `system_ext_b`,
`vendor_b`, `product_b`, `odm_b` = stock, byte-for-byte. Slot A partitions are empty, and
group `rockchip_dynamic_partitions_b` may use the whole super (stock caps each slot at 2.68 GB,
too small for KompaktOS). Stock `boot_b` (kernel + first-stage fstab) is unchanged; that
fstab mounts all five slot-B partitions without avb, so vbmeta is not touched.

## What is erased
- `super` (stock system for both slots; restorable from `~/InkPalm-Backup/partitions-full/super.img`)
- `userdata` + `metadata` (all apps/data, including the DSU test system). Files were backed up
  to `~/InkPalm-Backup` (sdcard, Android/data, APKs, app exports, screenshots).

## Steps (direct USB-C cable, not the hub)
1. `adb reboot fastboot`  → fastbootd (userspace; reports `unlocked: yes`)
2. Check: `fastboot getvar is-userspace` = yes, `fastboot getvar current-slot` = b
3. `fastboot flash super ~/InkPalm-Images/kompaktos/flash/super-kompaktos-vanilla.img`
   (the client resparses it into ≤64 MiB chunks)
4. `fastboot erase metadata` and `fastboot -w`   (clean data; also drops the DSU config)
5. `fastboot reboot`  — first boot can take several minutes on e-ink with no feedback.

## Revert to stock
Same steps with `~/InkPalm-Backup/partitions-full/super.img` in step 3, then `-w`, reboot,
restore files from `~/InkPalm-Backup` (see its README). `boot_b`, `vbmeta_b`, `dtbo_b` were
never changed, but their backups are in the same folder if ever needed.
