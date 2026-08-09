# device/samsung/a51 patches

Patches against `Parbindar7/android_device_samsung_a51` at
`b9b86945f85114ed28076602c49b83051337ff85` (branch `lineage-23.2`, the revision
pinned in `local_manifests/a51.xml`).

`0001`–`0006` are applied automatically by `crave-sync-build.sh` at PHASE 7b,
after both resyncs and after the `repo forall` deep clean. Any earlier
placement is undone by `git reset --hard`. Application is idempotent, so
re-running a job against a persisted workspace skips patches already present.
Disable with `A51_APPLY_PATCHES=0`.

`0007` and `0008` are **written but deliberately not wired in** — see below.

All are public-source only: no credentials, keys, or proprietary data.

## Applying manually

```bash
cd device/samsung/a51
git am /path/to/patches/device_samsung_a51/000[1-6]*.patch
```

## Active — 0001 to 0006

### 0001 — releasetools: write `vbmeta.img` during OTA install

`BoardConfig.mk:30` sets `TARGET_RELEASETOOLS_EXTENSIONS` to the device
releasetools, masking `universal9611-common`'s. The common extension installs
both `dtbo.img` and `vbmeta.img`; the device one installed only `dtbo.img`, so
generated OTA packages never wrote vbmeta at all. Verified still true against
`universal9611-common` `lineage-24.0` (`f2dffabd`).

The defect masks itself during development — a device already carrying a
patched vbmeta keeps it across every test flash. It only surfaces for a user
installing onto a stock vbmeta.

### 0002 — declare the super partition size the hardware actually has

`BoardConfigCommon.mk:114/116` declare `6836715520` / `6832521216`.
Byte-identical on 23.2 and 24.0, so pre-existing and not introduced by the port.

`lpdump` on a retail SM-A515F reports a physical super of **6382682112** bytes
— **454,033,408 smaller than declared**. `lpmake` will emit an image sized to
the declared value, which then cannot be flashed.

| partition | bytes |
|---|---|
| system | 1,970,216,960 |
| system_ext | 1,788,952,576 |
| product | 1,490,546,688 |
| vendor | 175,431,680 |
| odm | 487,424 |
| allocated | 5,425,635,328 |
| super | 6,382,682,112 |
| free | 957,046,784 |

Confirm with `lpdump` on your own unit before relying on these.
`BOARD_SAMSUNG_DYNAMIC_PARTITIONS_SIZE` leaves 4 MiB for metadata.

### 0003 — stop truncating the camera `extra_ids` list

`soong_config_set` takes exactly three arguments and uses `$(strip $3)`. Commit
`135a70f` (2025-05-15) rewrote

    SOONG_CONFIG_samsungCameraVars_extra_ids := 4,20,23,50,52,54

as a three-argument call with six comma-separated values, so `20 23 50 52 54`
land in `$4..$8` and are silently discarded — `extra_ids` resolves to just `4`.

Fixed by escaping the separators with `$(comma)`.

> ⚠️ **Do not define `comma` locally.** AOSP defines it in
> `build/make/common/core.mk` and marks it `.KATI_READONLY`. An earlier version
> of this patch added `comma := ,` and failed the entire product config with
> `BoardConfig.mk:45: error: cannot assign to readonly variable: comma`, which
> in turn produced `** Don't have a product spec for: 'lineage_a51'`.

This affects the current `lineage-23.2` tree, not only the Android 17 port, and
is worth sending upstream as a standalone fix.

### 0004 — drop the dangling public sepolicy directory

`sepolicy/public/property.te` was removed by `92a0ad4` ("a51: Drop
UdfpsHandler") and never re-added. The tree ships only
`sepolicy/vendor/file_contexts`, so `SYSTEM_EXT_PUBLIC_SEPOLICY_DIRS` points at
nothing.

### 0005 — Android 17 VINTF and kernel requirement compatibility

- `VENDOR_SECURITY_PATCH := $(PLATFORM_SECURITY_PATCH)` — the vendor blobs come
  from `A515FXXU8HWK1`, vendor patch level `2023-08-01`. Reporting a three-year
  old vendor patch level against an Android 17 platform fails VINTF.
- `PRODUCT_OTA_ENFORCE_VINTF_KERNEL_REQUIREMENTS := false` — belt-and-braces.
  `universal9611-common/manifest.xml:2` already declares
  `<kernel target-level="legacy"/>`, which exempts the kernel from FCM
  kernel-requirement checking.

### 0006 — inherit a 4 GB dalvik heap profile

Nothing in the inherit chain sets a device heap profile, so the build takes
untuned AOSP defaults. SM-A515F ships in 4/64, 6/128 and 8/128 configurations;
target the smallest, since an oversized heap on a 4 GB unit costs more in swap
pressure than a conservative heap costs the larger variants.

## Held — 0007 and 0008

Present in this directory but **not** listed in `crave-sync-build.sh`. Add the
filename to the `A51_PATCHES` array to activate.

### 0007 — pin the kernel toolchain to LLVM 21 · HOLD

lineage-24.0 resolves the kernel compiler to `clang-r584948` (LLVM 22.0.0);
this kernel has only ever shipped against `clang-r563880c` (LLVM 21.0.0) on
lineage-23.2. Both prebuilts exist at `android-17.0.0_r1`, so pinning needs no
download.

**Held on purpose.** The kernel already carries the LLVM modernisation series,
and `LineageOS/android_device_samsung_a21s` builds an Exynos 850 / 4.19 kernel
on lineage-24.0 with no pin at all. LLVM 22 may simply work — pinning
pre-emptively means never finding out.

Apply if the kernel fails to compile. Residual hazard: kernel `Makefile:564`
adds `-Werror=unknown-warning-option`, so any `-Wno-<name>` LLVM 22 renamed
becomes a hard error; relief belongs in `TARGET_KERNEL_ADDITIONAL_FLAGS`, which
`kernel.mk:275-277` appends last. **Never set `LLVM_IAS=0`** — lineage-24.0
ships no GNU `as`.

### 0008 — correct the XML declaration in the framework matrix · HOLD

`configs/vintf/device_framework_matrix.xml` declared `<?xml version="2.0"?>`.
No such XML version exists. tinyxml2 tolerates it today. The
`compatibility-matrix` element's own `version="2.0"` is a separate, valid VINTF
schema version and is left alone.

Cosmetic today; held only to keep the active set to changes with a demonstrated
need.

## Not addressed

Tracked in [`A51_PRODUCT_SPEC.md`](../../A51_PRODUCT_SPEC.md) §8: FCM
`target-level="6"`, fingerprint AIDL pinned to V4, the vendor tree having no
`lineage-24.0` branch, absent `ccache`, the AVB test key, duplicated overlay
resources, and `extract-files.py` shadowing its `lib_fixups` defaults.
