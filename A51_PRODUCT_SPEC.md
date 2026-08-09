# SM-A515F / `a51` — product specification reference

Working reference for the Evolution X 12.1 (Android 17) forward-port. Every
value below was read out of source at the pinned revisions or measured on a
retail handset — nothing here is inferred from documentation.

**Baseline revisions**

| project | branch | revision |
|---|---|---|
| `device/samsung/a51` | `lineage-23.2` | `b9b86945` (2026-03-21) |
| `device/samsung/universal9611-common` | `lineage-24.0` | `f2dffabd` (2026-08-05) |
| `kernel/samsung/universal9611` | `lineage-24.0` | `9c4dcd26` (2026-08-06) |
| `vendor/samsung/a51` | `lineage-23.2` | `7aa200a4` |
| `vendor/samsung/universal9611-common` | `lineage-23.2` | `b06ea9e0` |
| Evolution X manifest | `cnb` | `05755535` |

`lineage-24.0` on the common tree is a fast-forward of `lineage-23.2` plus five
commits touching four files. It imposes no requirements on the device tree.
No device tree for **any** Exynos 9611 device (a51, m21, m31, m31s, f41) exists
on an Android 17 branch anywhere.

---

## 1. Build target

```
lunch lineage_a51-cp2a-user
```

| | |
|---|---|
| product | `lineage_a51` |
| device | `a51` |
| release config | `cp2a` (Android 17) |
| variant | `user` |
| `EVO_BUILD_TYPE` | `Unofficial` |
| `WITH_GMS` | **must be set explicitly** |

`WITH_GMS` has no `?=` default at `vendor_evolution` `e870fbc2`. Unset fires
neither the `ifeq true` nor the `ifeq false` branch and produces an unaudited
in-between product. Always pass `true` or `false`.

## 2. Product identity — `lineage_a51.mk`

```make
PRODUCT_NAME              := lineage_a51
PRODUCT_DEVICE            := a51
PRODUCT_BRAND             := samsung
PRODUCT_MODEL             := SM-A515F
PRODUCT_MANUFACTURER      := samsung
PRODUCT_SHIPPING_API_LEVEL := 29
PRODUCT_GMS_CLIENTID_BASE := android-samsung-ss
TARGET_BOOT_ANIMATION_RES := 1080

TARGET_HAS_FOD       := true
TARGET_HAS_NFC       := true
TARGET_USES_NXP_NFC  := true
```

Build fingerprint spoof (Android 13):

```
samsung/a51nsxx/a51:13/TP1A.220624.014/A515FXXU5GVK6:user/release-keys
```

Note this is `A515FXXU5GVK6` while the proprietary blob lists are primarily
from `A515FXXU8HWK1`. Intentional — the fingerprint is a spoof, the donor is
the blob source.

## 3. Inherit chain

```
lineage_a51.mk
 ├─ device/samsung/a51/device.mk
 │   ├─ device/samsung/universal9611-common/common.mk
 │   │   ├─ $(SRC_TARGET_DIR)/product/non_ab_device.mk
 │   │   ├─ $(SRC_TARGET_DIR)/product/core_64_bit_only.mk
 │   │   ├─ vendor/samsung/universal9611-common/universal9611-common-vendor.mk
 │   │   ├─ hardware/samsung_slsi-linaro/config/config.mk
 │   │   └─ $(SRC_TARGET_DIR)/product/emulated_storage.mk
 │   └─ vendor/samsung/a51/a51-vendor.mk
 ├─ $(SRC_TARGET_DIR)/product/full_base_telephony.mk
 ├─ vendor/lineage/config/common_full_phone.mk
 └─ frameworks/native/build/phone-xhdpi-4096-dalvik-heap.mk   [patch 0006]
```

`core_64_bit_only.mk` means this is a **64-bit-only build**. No 32-bit runtime;
32-bit-only apps will not run.

## 4. Hardware

| | |
|---|---|
| SoC | Exynos 9611 (`universal9611`), Cortex-A73 + A53 |
| `TARGET_CPU_VARIANT` | `cortex-a73` (set in common tree) |
| kernel | **Linux 4.14** |
| ABI | `arm64-v8a`, 64-bit only |
| RAM | 4 / 6 / 8 GB variants; reference unit **4 GB** |
| fingerprint | optical UDFPS, `540\|2145\|114` |
| NFC | NXP, AIDL sec nfc |
| boot mode | non-A/B, dynamic partitions |
| encryption | FBE v2 + metadata encryption |
| filesystems | ext4 system/system_ext/product · EROFS vendor/odm · F2FS userdata |

Treble state read from a retail handset:

```
ro.treble.enabled           true
ro.product.cpu.abi          arm64-v8a
ro.boot.dynamic_partitions  true
ro.vndk.version             (empty)   post-VNDK
ro.vndk.lite                (empty)   not vndklite
ro.vendor.api_level         29
ro.board.api_level          202504
```

Treble Info reports the required image type as **`system-arm64-ab.img.xz`** —
arm64, system-as-root. The `a`/`b` in GSI naming is system-as-system vs
system-as-root, **not** partition slots; this device is non-A/B on slots and
still needs the `b` variant.

## 5. Partition geometry

**Declared** — `universal9611-common/BoardConfigCommon.mk`:

```make
BOARD_SUPER_PARTITION_SIZE            := 6836715520   # :114
BOARD_SAMSUNG_DYNAMIC_PARTITIONS_SIZE := 6832521216   # :116
```

Byte-identical on `lineage-23.2` and `lineage-24.0` — pre-existing, not
introduced by the port.

**Measured** — `lpdump` on a retail SM-A515F:

| | bytes |
|---|---|
| super (physical) | **6,382,682,112** |
| system | 1,970,216,960 |
| system_ext | 1,788,952,576 |
| product | 1,490,546,688 |
| vendor | 175,431,680 |
| odm | 487,424 |
| allocated | 5,425,635,328 |
| free | 957,046,784 |

⚠️ **The declared super is 454,033,408 bytes larger than the hardware has.**
`lpmake` will emit an image that cannot be flashed. The group maximum in the
on-device metadata (6,832,521,216) also exceeds the physical super by
449,839,104 bytes — that capacity is unbacked. Patch 0002 overrides both.

Fixed image sizes — `device/samsung/a51/BoardConfig.mk:33-36`:

```
boot     <=  61,865,984   header v2, DTB in boot
recovery <=  71,106,560   full separate recovery
dtbo     <=   8,388,608
cache        209,715,200
```

`TARGET_OTA_ASSERT_DEVICE` (`BoardConfig.mk:25`): `a51,a51dd,a51nsxx`. Alias
presence is not proof of variant compatibility.

## 6. Device tree contents

53 files. Nothing in it references `schedtune`, `/dev/freezer`, `task_profiles`,
`cgroups`, `vndk`, `media_codecs`, `media_profiles`, `powerhint`,
`TARGET_USES_VULKAN`, `TARGET_CPU_VARIANT` or `fsconfig` — verified by grep, so
none of the common tree's recent churn in those areas conflicts.

- `PRODUCT_COPY_FILES` destinations: 101 common vs 6 device — **0 collisions**
- `vendor.prop` keys: 59 common vs 4 device — **0 duplicates**
- `configs/kernel/a51.cfg` present (required by `BoardConfigCommon.mk:72`)
- ships no `.te` files; only `sepolicy/vendor/file_contexts`

The only device-supplied switches the common tree reads are `TARGET_HAS_NFC`,
`TARGET_USES_NXP_NFC` and `TARGET_USES_SLSI_NFC`. The first two are set.

## 7. Patch set

Applied automatically at PHASE 7b, after both resyncs and after the `repo
forall` deep clean. Earlier placement would be undone by `git reset --hard`.

| | change | why |
|---|---|---|
| 0001 | write `vbmeta.img` in `OTA_InstallEnd` | `BoardConfig.mk:30` overrides `TARGET_RELEASETOOLS_EXTENSIONS`, masking the common extension. Common installs dtbo **and** vbmeta; the device one installed only dtbo, so OTAs never wrote vbmeta. Confirmed still true on `lineage-24.0`. Self-masking during development — a device already carrying a patched vbmeta keeps it across every test flash. |
| 0002 | real super partition size | see §5 |
| 0003 | camera `extra_ids` | `soong_config_set` takes 3 args and uses `$(strip $3)`. `135a70f` (2025-05-15) rewrote a plain assignment as a call with 6 comma-separated values; `20 23 50 52 54` land in `$4..$8` and are discarded, leaving `extra_ids = 4`. Escaped with `$(comma)` — **do not define `comma` locally, it is `.KATI_READONLY` in `build/make/common/core.mk`** and reassigning it fails product config. |
| 0004 | drop dangling `sepolicy/public` | removed by `92a0ad4` ("Drop UdfpsHandler"), never re-added |
| 0005 | `VENDOR_SECURITY_PATCH := $(PLATFORM_SECURITY_PATCH)` + `PRODUCT_OTA_ENFORCE_VINTF_KERNEL_REQUIREMENTS := false` | vendor patch level is 2023-08-01 against an A17 platform — fails VINTF. Kernel 4.14 fails A17's OTA kernel requirement check. |
| 0006 | inherit `phone-xhdpi-4096-dalvik-heap.mk` | nothing in the chain sets a heap profile; build takes untuned defaults. Target the smallest variant. |

0003 is a defect in the current `lineage-23.2` tree affecting every Exynos 9611
device and is worth sending upstream on its own.

## 8. Open questions

Revised after direct inspection of `lineage-24.0` build system source. The
kernel/toolchain risk is **substantially lower** than the first revision of
this document claimed.

### Resolved

**Kernel VINTF requirements — not an issue.** `universal9611-common/manifest.xml`
line 2 is `<kernel target-level="legacy"/>`, the standard exemption from FCM
kernel-requirement checking. Already upstream. Patch 0005's
`PRODUCT_OTA_ENFORCE_VINTF_KERNEL_REQUIREMENTS := false` is belt-and-braces on
top of it.

**No kernel version gate exists.** Every `TARGET_KERNEL_VERSION` conditional in
`vendor/lineage/build/tasks/kernel.mk` @ lineage-24.0 (lines 137-140, 177,
741-754) is nested inside `ifeq ($(BOARD_USES_QCOM_HARDWARE),true)` or inside
`ifneq ($(TARGET_KERNEL_PLATFORM_TARGET),)`, neither of which applies here.
There is no minimum-kernel-version check to defeat.

**Kernel config present.** `exynos9611-a51_defconfig` exists on the kernel's
`lineage-24.0` branch. `configs/kernel/a51.cfg` (371 B) and
`configs/kernel/exynos9611.cfg` (61 B) exist in the **common** tree —
`BoardConfigCommon.mk:72,76` reference them via `$(COMMON_PATH)`, not the
device path.

**`TARGET_KERNEL_NO_GCC := true` is dead.** `vendor/lineage` commit
`21fb2c0ccda9` ("kernel: Rip out GCC support", 2026-07-02) removed
`TARGET_KERNEL_NO_GCC`, `TARGET_KERNEL_CLANG_COMPILE`,
`TARGET_KERNEL_LLVM_BINUTILS` and `TARGET_KERNEL_CROSS_COMPILE_PREFIX` from
lineage-24.0. `BoardConfigCommon.mk:84` still sets it; it is now a no-op.

### Open — kernel toolchain

`TARGET_KERNEL_CLANG_VERSION` is unset, so the kernel builds with whatever
clang lineage-24.0 resolves by default.

| branch | clang | LLVM |
|---|---|---|
| lineage-23.2 | `clang-r563880c` | 21.0.0 |
| **lineage-24.0** | `clang-r584948` | **22.0.0** |

**The delta is one LLVM major version**, not a nine-year gap. The kernel already
carries the LLVM modernisation series — `kbuild: support LLVM=1`, `Makefile:
infer --target from ARCH for CC=clang`, `LLVM_IAS=1` by default, and
`UPSTREAM: kbuild: Disable -Wdefault-const-init-unsafe` (the Clang 21
breakage, already applied).

Precedent: `LineageOS/android_device_samsung_a21s` is on `lineage-24.0` with an
Exynos 850 / kernel **4.19.325** and **no clang pin**. An Exynos device with an
old kernel already builds on this branch against default LLVM 22.

Residual hazard is narrow: kernel `Makefile:564` adds
`-Werror=unknown-warning-option`, so any `-Wno-<name>` that LLVM 22 renamed or
dropped becomes a hard error.

**Mitigation ladder — do not pre-apply.**

0. Build unmodified. Kernel and device tree are effectively identical between
   23.2 and 24.0; only LLVM 22 is untested.
1. **Patch 0007 (written, deliberately unwired):**
   `TARGET_KERNEL_CLANG_VERSION := r563880c`. Both prebuilts ship at
   `android-17.0.0_r1` (`r547379`/LLVM 20, `r563880c`/21, `r584948`/22,
   `r584948b`, `r596125`, `clang-stable`) so no download is needed.
2. Targeted relief — `kernel.mk:275-277` appends
   `TARGET_KERNEL_ADDITIONAL_FLAGS` **last**, so it overrides the unconditional
   `LLVM=1 LLVM_IAS=1` at line 129:
   `TARGET_KERNEL_ADDITIONAL_FLAGS := KCFLAGS="-Wno-error=unknown-warning-option ..."`
   Use `+=` on any subsequent line, never a second `:=`.
3. `KERNEL_LTO := none` if lld or LTO is the failure (`kernel.mk:317-341`).
4. External toolchain via `TARGET_KERNEL_CLANG_PATH` (`BoardConfigKernel.mk:80`
   is `?=`, so a device value wins and PATH/LD_LIBRARY_PATH follow).

⚠️ **Never set `LLVM_IAS=0`** — lineage-24.0 ships no GNU `as`, so
`-no-integrated-as` will fail to find an assembler.

### Open — FCM target level

`universal9611-common/manifest.xml:1` is `target-level="6"` (Android 12). AOSP
retires FCM levels over time; if 17 no longer accepts 6, `check_vintf` fails.
Common-tree issue, not device-tree. Ladder: try as-is → bump `target-level`
incrementally, accepting that each level adds mandatory HAL requirements →
`PRODUCT_ENFORCE_VINTF_MANIFEST := false` as the escape hatch. Do not set the
escape hatch pre-emptively; it masks problems worth seeing.

### Open — fingerprint AIDL

`fingerprint/Android.bp:25-26` and the vintf fragment pin
`android.hardware.biometrics.fingerprint-V4-ndk` / `<version>4</version>`. If
AOSP 17 freezes V5, both need bumping and `Fingerprint.cpp` / `Session.cpp`
rebuilding against the new interface. Upstream
`hardware/samsung/aidl/fingerprint` is also still on V4 — no upstream answer
exists. Needs the real AOSP 17 tree.

### Open — vendor tree generation gap

`vendor/samsung/universal9611-common` and `vendor/samsung/a51` have **no
`lineage-24.0` branch** — only `lineage-23.2`. The build pairs 23.2-era vendor
blobs with a 24.0 common tree. This is the most likely source of runtime
(rather than build-time) failure.

### Non-blocking

- `ccache` absent on the Crave worker (`Error: ccache not found`). Every
  rebuild is a full rebuild — significant across many iterations.
- `BoardConfigCommon.mk:192` — `BOARD_AVB_RECOVERY_KEY_PATH` still points at
  `external/avb/test/data/testkey_rsa4096.pem`. Development only.
- 8 resources defined in both device and common overlays
  (`config_autoBrightnessLevels`, `config_screenBrightnessDoze`,
  `config_supportDoubleTapWake` and five others). `device.mk:24` appends after
  the common overlay; verify which wins in `framework-res_intermediates`.
- `extract-files.py:30-32` shadows the imported `lib_fixups` defaults.
- `configs/vintf/device_framework_matrix.xml:1` declared `<?xml version="2.0"?>`
  — fixed by patch 0008 (written, unwired).
- `UdfpsHandler/include/UdfpsHandler.h` uses `std::string` without
  `#include <string>`.
- `BoardConfig.mk:47` references `//device/samsung/a51:libudfps_extension.a51`
  while a51 declares no `soong_namespace`. **Not a break** — Soong resolves in
  the root namespace, same as `android_device_samsung_a71`. Leave it.

### Ecosystem context

No device tree for any Exynos 9611 codename (a51, m21, m31, m31s, f41) exists
on any Android 17 branch anywhere. Evolution X `cnb` is real and shipping, but
for roughly 26 devices, all Xiaomi Snapdragon — **zero Samsung, zero Exynos** in
Evolution-X-Devices. In the LineageOS org the only Samsung `lineage-24.0`
device trees are `sm8550-common`, `sm8250-common` (both Qualcomm) and `a21s`
(Exynos 850). `Parbindar7/android_hardware_samsung_slsi-linaro_exynos` on
`lineage-24.0` has real commits through 2026-07-04 and is likely the furthest
along Exynos Android 17 work in existence.

No public prebuilt Android 17 kernel exists for Exynos.

## 9. Verification

On the handset:

```bash
adb shell lpdump                       # partition geometry
adb shell getprop ro.vendor.api_level
adb shell getprop ro.board.api_level
adb shell getprop ro.boot.verifiedbootstate
adb shell getprop ro.boot.veritymode
```

After a build:

```bash
lpdump --image out/target/product/a51/super.img
avbtool info_image --image out/target/product/a51/vbmeta.img
unpack_bootimg --boot_img out/target/product/a51/boot.img
```

Audit image sizes against §5 using the **measured** super, not the value in
`BoardConfigCommon.mk`.

## 10. Build history

| job | outcome |
|---|---|
| 292024 | exit 130 — client disconnect, not detached. Not a failure or a moderator action. |
| 292171 | stale carrier manifest state: `revision refs/heads/master in manifests not found`, then missing `device/qcom/sepolicy_vndr/sm8650` |
| 292268 | 20m10s — `prebuilts/gcc/.../arm-linux-androideabi-4.9: Cannot remove project: uncommitted changes are present`. resync clears one blocked project per pass; two fixed passes cannot converge. Fixed by `resync_with_pruning()`. |
| (next) | 23m20s — reached **PHASE 8 / product config** for the first time. Both resyncs succeeded on attempt 1; all four patches applied. Died on `BoardConfig.mk:45: cannot assign to readonly variable: comma` — a defect in patch 0003, since fixed. |

The `error: hooks is different in .repo/projects/X vs .repo/project-objects/Y`
messages (85 of them) appear on every run and are **non-fatal** — repo continues
past all of them. They indicate `.repo` metadata still carries LOS22-era
project→object mappings. If a future run fails somewhere new during sync, this
is the first suspect, and the fix would be pruning those metadata directories
rather than the working trees.
