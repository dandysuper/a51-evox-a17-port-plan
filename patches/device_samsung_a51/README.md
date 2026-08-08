# device/samsung/a51 patches

Patches against `Parbindar7/android_device_samsung_a51` at
`b9b86945f85114ed28076602c49b83051337ff85` (branch `lineage-23.2`, the revision
pinned in `local_manifests/a51.xml`).

All four apply cleanly with `git am` in that order. They are public-source only
and contain no credentials, keys, or proprietary data.

## Applying

```bash
cd device/samsung/a51
git am /path/to/patches/device_samsung_a51/*.patch
```

## Contents

### 0001 - releasetools: write vbmeta.img during OTA install

`BoardConfig.mk:30` sets `TARGET_RELEASETOOLS_EXTENSIONS` to the device
releasetools, masking `universal9611-common`'s extension. The common extension
installs both `dtbo.img` and `vbmeta.img`; the device one installed only
`dtbo.img`, so generated OTA packages never wrote vbmeta at all.

Verified still true against `universal9611-common` `lineage-24.0`
(`f2dffabd`): common `BoardConfigCommon.mk:162` vs device `BoardConfig.mk:30`.

Note this defect masks itself during development - a device already carrying a
patched vbmeta keeps it across every test flash. It only surfaces for a user
installing onto a stock vbmeta.

### 0002 - declare the super partition size the hardware actually has

`BoardConfigCommon.mk:114` declares `BOARD_SUPER_PARTITION_SIZE := 6836715520`
and `:116` `BOARD_SAMSUNG_DYNAMIC_PARTITIONS_SIZE := 6832521216`. Byte-identical
on `lineage-23.2` and `lineage-24.0`, so this is pre-existing and not introduced
by the Android 17 port.

`lpdump` on a retail SM-A515F reports a physical super of **6382682112** bytes -
**454033408** bytes smaller than declared. `lpmake` will emit a super image
sized to the declared value, which then cannot be flashed.

Measured layout on the reference handset:

| partition   | bytes         |
|-------------|---------------|
| system      | 1,970,216,960 |
| system_ext  | 1,788,952,576 |
| product     | 1,490,546,688 |
| vendor      |   175,431,680 |
| odm         |       487,424 |
| allocated   | 5,425,635,328 |
| super       | 6,382,682,112 |
| free        |   957,046,784 |

Confirm against your own hardware with `lpdump` before relying on these values;
`BOARD_SAMSUNG_DYNAMIC_PARTITIONS_SIZE` here leaves 4 MiB for metadata.

### 0003 - stop truncating the camera extra_ids list

`soong_config_set` takes exactly three arguments and uses `$(strip $3)`.
Commit `135a70f` (2025-05-15) rewrote

    SOONG_CONFIG_samsungCameraVars_extra_ids := 4,20,23,50,52,54

as

    $(call soong_config_set,samsungCameraVars,extra_ids,4,20,23,50,52,54)

The unquoted commas split the argument list, so `20 23 50 52 54` land in
`$4..$8` and are silently discarded - `samsungCameraVars.extra_ids` resolves to
just `4`.

This affects the current `lineage-23.2` tree, not only the Android 17 port, and
is likely worth sending upstream as a standalone fix.

### 0004 - drop the dangling public sepolicy directory

`sepolicy/public/property.te` was removed by `92a0ad4` ("a51: Drop
UdfpsHandler") and never re-added. The tree now ships only
`sepolicy/vendor/file_contexts`, so `SYSTEM_EXT_PUBLIC_SEPOLICY_DIRS` points at
a directory that does not exist.

## Not addressed here

These need a real build or the AOSP 17 tree to resolve:

- **Fingerprint AIDL pinned to V4.** `fingerprint/Android.bp:25-26` and the
  vintf fragment use `android.hardware.biometrics.fingerprint-V4-ndk`. If
  Android 17 freezes V5, both need bumping and `Fingerprint.cpp` / `Session.cpp`
  need rebuilding against the new interface. Upstream
  `hardware/samsung/aidl/fingerprint` is also still on V4, so there is no
  upstream answer yet.
- **FCM target level.** `universal9611-common/manifest.xml:1` is
  `target-level="6"` (Android 12). AOSP retires old FCM levels; if 17 drops 6,
  `check_vintf` fails. This is a common-tree issue, not a device-tree one.
- **Overlay precedence.** Eight resources are defined in both the device and
  common overlays (`config_autoBrightnessLevels`,
  `config_screenBrightnessDoze`, `config_supportDoubleTapWake`, and five
  others). Pre-existing, but worth settling given recent common-tree brightness
  changes.
- **AVB recovery key.** `BoardConfigCommon.mk:192` still points at
  `external/avb/test/data/testkey_rsa4096.pem`. Acceptable for development
  only; a release build needs controlled keys.
