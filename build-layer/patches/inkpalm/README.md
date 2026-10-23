# InkPalm patch series

Our changes to LineageOS / TrebleDroid projects, applied by `build-layer/build.sh` **after**
upstream KompaktOS's own series (`patches/kompakt/`, applied with its `apply-patches.sh`).
Empty for now.

## Format (same as upstream KompaktOS)

```
patches/inkpalm/<project>/NNNN-short-subject.patch
```

- `<project>` is the project's tree path with `/` written as `_`, using upstream's names:
  `frameworks_base`, `device_phh_treble`, `packages_apps_Settings`, `system_sepolicy`, ...
  The name -> path table is read from upstream's `patches/apply-patches.sh`; a project it does
  not list needs a line in `projects.map` here (`<name> <path>`).
- Files are a `git format-patch` series, applied in name order with
  `git am --keep-non-patch`, so they keep their messages and authorship and can be rebased when
  LineageOS or KompaktOS moves. One logical change per patch, message says why.
- Make them against a tree that already has the KompaktOS series applied (build.sh's `patch`
  stage leaves exactly that): commit in the project, then
  `git -C $TREE/<path> format-patch -o build-layer/patches/inkpalm/<project>/ --start-number N <base>..HEAD`.

build.sh hashes this directory; when anything here changes, the next run resets the touched
projects to the manifest revision (no network) and re-applies both series. A patch that no longer
applies stops the build with the project name.

## Candidates (not written yet)

- `device_phh_treble`: move `vendor/inkpalm/sepolicy/file_contexts` here instead of build.sh's
  marker-block injection, plus the sepolicy that retires the root e-ink bridge (platform_app may
  write the aw99703 frontlight nodes).
- `device_phh_treble`: re-enable the AOSP charger in charging mode (upstream 0006 disables it for
  the Mudita charger, which cannot run on the rk3566). UNVERIFIED whether the AOSP charger draws
  anything sensible on the e-ink panel.
- A keylayout for the capacitive button (key code not captured yet, docs/HANDOFF.md).
