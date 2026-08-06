# Samsung Galaxy A51 - Evolution X 12.1 / Android 17 port plan

**Version:** v2 (verified and corrected)
**Prepared:** 2026-08-05 (v1); revised 2026-08-05 (v2)
**Scope:** research and implementation plan only
**Current state:** no ROM source was synced, edited, or built. Phase 1 draft artifacts (pinned local manifest, `evolution.dependencies`, fork script) now exist in the accompanying `port-kit/` directory.

**v2 changelog** (all changes backed by live source checks on 2026-08-05; see Appendix A):

1. Corrected §3.1/§2: `WITH_GMS` has **no default** at the pinned vendor revision — the v1 claim "defaults to true" was wrong.
2. Corrected §3.4 attribution: boot/recovery/dtbo/cache sizes live in `device/samsung/a51/BoardConfig.mk`, not the common BoardConfig.
3. Confirmed the Phase 5 releasetools defect in code (device extension masks the common vbmeta write) — upgraded from suspicion to verified fact.
4. Confirmed the recovery AVB test key (`BoardConfigCommon.mk:192`).
5. Confirmed kernel version precisely: Linux **4.14.356**.
6. Replaced the stale macOS workspace note with the chosen build-host strategy (Oracle Cloud trial VM / Crave).
7. Added Appendix A (verification log) and §9 pointer to the drafted Phase 1 files.

## 1. Executive decision

This port is technically possible as an experimental, unofficial build, but it is not a manifest-only port. It is an Android 17 forward-port of an A51 device/vendor stack whose public pieces are split between `lineage-23.2` and `lineage-24.0`, with no public end-to-end Android 17 A51 boot proof.

The recommended architecture is:

1. Use Evolution X `cnb` as the Android 17/Evolution X 12.1 base.
2. Fork the A51-specific trees into a controlled organization and create `cnb` branches pinned to known source commits.
3. Start the common tree and kernel from the public Android 17-oriented `lineage-24.0` revisions.
4. Forward-port only the needed later common-tree semantics from `lineage-23.2`; do not merge the entire older branch.
5. Keep the proven Samsung non-A/B, dynamic-partition, FBE, HWC3, UDFPS, RIL, and camera design while adapting build/API/sepolicy interfaces to Android 17.
6. Bring up recovery and the boot chain before flashing `super` or attempting a normal system boot.
7. Release only after clean install, encryption, hardware tests, OTA, rollback, and security gates pass on real SM-A515F hardware.

The first release target should be **SM-A515F / `a51` only**, with an **unofficial** build type. Do not advertise A515FN, A515G, A515GN, A51 5G, VoLTE, or VoWiFi until those are separately proven.

## 2. Fixed support contract

| Item | Initial decision | Why it matters |
|---|---|---|
| Device | Samsung Galaxy A51 4G, `SM-A515F`, codename `a51` | The source tree and blob donor are for this model. |
| ROM | Evolution X 12.1, Android 17, manifest branch `cnb` | Evolution's version file reports Android `17.0` and `EVO_VERSION_BASE := 12.1`. |
| Base revisions | AOSP `android-17.0.0_r1`, Lineage base `lineage-24.0` | These are selected by Evolution's `cnb` manifest. |
| Product name | Keep `lineage_a51`; target device remains `a51` | Evolution's Android 17 build scripts still use Lineage-style product names. |
| Build type | `EVO_BUILD_TYPE := Unofficial` | Official signing, OTA, and device registration are separate Evolution X processes. |
| Partition model | Non-A/B, dynamic `super`, separate `boot`, `recovery`, `dtbo`, and `vbmeta` | The device fstab and BoardConfig do not describe an A/B device. |
| Initial firmware donor | Samsung package `A515FXXU8HWK1` | Both device and common proprietary lists identify this package as the primary donor. |
| Minimum firmware assertion | Existing `board-info.txt` requires bootloader token `G` and the updater reports One UI 5 firmware | Samsung rollback protection prevents arbitrary bootloader downgrades. Verify this on the test phone before flashing. |
| First GMS variant | Vanilla (`WITH_GMS=false`) for bring-up; GMS only after size audit | **Always pass `WITH_GMS` explicitly.** At the pinned vendor revision there is no `WITH_GMS ?=` default: an unset value fires neither the GMS (`ifeq true`) nor the Vanilla (`ifeq false`) branches, producing an unaudited in-between product. Dynamic-group fit is not yet proven. |
| Telephony claim | RIL/SIM/LTE data are targets; Samsung IMS/VoLTE/VoWiFi are unsupported until separately implemented | RIL registration is not evidence that IMS voice works. |

Before implementation, freeze one test handset, its exact model string, bootloader binary, baseband, storage layout, and complete stock firmware package. Do not use a developer's only phone.

## 3. Research findings

### 3.1 Evolution X Android 17 base

Verified sources:

- [Evolution-X/manifest `cnb` commit `05755535`](https://github.com/Evolution-X/manifest/commit/05755535e93f9e83ebccbda790ccc94102d5abec)
  - `default.xml` uses AOSP `android-17.0.0_r1`.
  - The default Lineage revision is `refs/heads/lineage-24.0`.
  - The branch README documents:

    ```bash
    repo init -u https://github.com/Evolution-X/manifest -b cnb --git-lfs
    repo sync -c -j$(nproc --all) --force-sync --no-clone-bundle --no-tags
    . build/envsetup.sh
    lunch lineage_codename-cp2a-user
    m evolution
    ```

- [Evolution-X/vendor_evolution `cnb` commit `506d2577`](https://github.com/Evolution-X/vendor_evolution/commit/506d2577f439d3d515bdb95ecbeba9821daa1008)
  - `PRODUCT_VERSION_MAJOR = 17` and `PRODUCT_VERSION_MINOR = 0`.
  - `EVO_VERSION_BASE := 12.1`.
  - `EVO_BUILD_TYPE` accepts only `Official` or `Unofficial`.
  - GMS packaging is gated by `ifeq ($(WITH_GMS),true)` blocks and `WITH_GMS=false` creates a Vanilla build. **Correction (verified 2026-08-05):** contrary to v1, there is no explicit `WITH_GMS ?=` default in `config/version.mk`, `config/common.mk`, `config/evolution.mk`, or `build/envsetup.sh` at commit `506d2577`. An unset `WITH_GMS` fires neither branch. Every build invocation must set `WITH_GMS=true` or `WITH_GMS=false` explicitly, and the resulting product graph must be audited per variant.

Evolution's roomservice reads `evolution.dependencies`, not `lineage.dependencies`. It recursively syncs dependencies and accepts explicit `remote`, `branch`, and exact `revision` values. A51 is absent from the Evolution-X-Devices repository search, so the device must be added through a local manifest or a later upstream device submission.

The `cnb` manifest maps Evolution's vendor project to the traditional path `vendor/lineage`. Keep existing product inheritance paths such as `vendor/lineage/config/common_full_phone.mk`; do not rename that path merely because the source repository is Evolution X.

### 3.2 Pinned device/source matrix

The following revisions are the research baseline. They are not yet forked or edited.

| Build path | Source | Source branch | Baseline revision | Port action |
|---|---|---:|---:|---|
| `device/samsung/a51` | [Parbindar7/android_device_samsung_a51](https://github.com/Parbindar7/android_device_samsung_a51/commit/b9b86945f85114ed28076602c49b83051337ff85) | `lineage-23.2` | `b9b86945f85114ed28076602c49b83051337ff85` | Fork and forward-port to `cnb`. |
| `device/samsung/universal9611-common` | [Parbindar7/android_device_samsung_universal9611-common](https://github.com/Parbindar7/android_device_samsung_universal9611-common/commit/0fad56bed7ab9933b2e31468207890e362191458) | `lineage-24.0` | `0fad56bed7ab9933b2e31468207890e362191458` | Use as the common A17-oriented base. |
| `kernel/samsung/universal9611` | [Parbindar7/android_kernel_samsung_universal9611](https://github.com/Parbindar7/android_kernel_samsung_universal9611/commit/1dfd9ef8149baac442dffe6cdf69de3ff3665bb4) | `lineage-24.0` | `1dfd9ef8149baac442dffe6cdf69de3ff3665bb4` | Fork/pin; verify the exact kernel version and cnb toolchain compatibility. |
| `vendor/samsung/a51` | [Parbindar7/android_vendor_samsung_a51](https://github.com/Parbindar7/android_vendor_samsung_a51/commit/7aa200a45ebbc2705f51d9740410ba16dab40d26) | `lineage-23.2` | `7aa200a45ebbc2705f51d9740410ba16dab40d26` | Fork/pin; re-extract only after the donor firmware is frozen. |
| `vendor/samsung/universal9611-common` | [Parbindar7/android_vendor_samsung_universal9611-common](https://github.com/Parbindar7/android_vendor_samsung_universal9611-common/commit/b06ea9e0d14871a32de0b87ed0d4e24809751336) | `lineage-23.2` | `b06ea9e0d14871a32de0b87ed0d4e24809751336` | Keep paired with common `0fad56be`; media profiles/codecs were moved into the device tree. |
| `hardware/samsung_slsi-linaro/exynos` | [Parbindar7/android_hardware_samsung_slsi-linaro_exynos](https://github.com/Parbindar7/android_hardware_samsung_slsi-linaro_exynos/commit/2eea770ae16ce0a726710d6a663e9de39b6aaeac) | `lineage-24.0` | `2eea770ae16ce0a726710d6a663e9de39b6aaeac` | Use the KeyMint V5 Android 17 migration; fork only if patched. |
| `hardware/samsung_slsi-linaro/graphics` | [LineageOS base](https://github.com/LineageOS/android_hardware_samsung_slsi-linaro_graphics/commit/703d69fc4c6e2f59ca2069608ea26c564c6e12a7) | `lineage-24.0` | `703d69fc4c6e2f59ca2069608ea26c564c6e12a7` | Use as base; manually rebase transparent-layer behavior from [`7ee3ed4e`](https://github.com/Parbindar7/android_hardware_samsung_slsi-linaro_graphics/commit/7ee3ed4eebbcf0f14d62fd79d92978798f7fcac7). Do not import the stale whole 23.2 fork. |

### 3.3 Lineage-24 Samsung/SLSI dependencies

Pin these direct dependencies to the following Lineage `lineage-24.0` revisions unless a port patch forces a controlled fork:

| Build path | Revision |
|---|---:|
| `device/samsung_slsi/sepolicy` - [`ac6a195c`](https://github.com/LineageOS/android_device_samsung_slsi_sepolicy/commit/ac6a195ccc08d2fbcd3580924f25e4b289ae7025) | `ac6a195ccc08d2fbcd3580924f25e4b289ae7025` |
| `hardware/samsung` - [`b03c9487`](https://github.com/LineageOS/android_hardware_samsung/commit/b03c9487519e20a9040821297de51d1297e19b7b) | `b03c9487519e20a9040821297de51d1297e19b7b` |
| `hardware/samsung_slsi/libbt` - [`372d43a2`](https://github.com/LineageOS/android_hardware_samsung_slsi_libbt/commit/372d43a231237a8134b2cc4ec6659089e22f4f59) | `372d43a231237a8134b2cc4ec6659089e22f4f59` |
| `hardware/samsung_slsi-linaro/config` - [`3626ce71`](https://github.com/LineageOS/android_hardware_samsung_slsi-linaro_config/commit/3626ce714e847cae429883a612d4ec9de79389e7) | `3626ce714e847cae429883a612d4ec9de79389e7` |
| `hardware/samsung_slsi-linaro/exynos5` - [`7a7c9823`](https://github.com/LineageOS/android_hardware_samsung_slsi-linaro_exynos5/commit/7a7c982313e0821898ef9c696d3e12da95cfe037) | `7a7c982313e0821898ef9c696d3e12da95cfe037` |
| `hardware/samsung_slsi-linaro/interfaces` - [`aa39734c`](https://github.com/LineageOS/android_hardware_samsung_slsi-linaro_interfaces/commit/aa39734cbeb5ea14a28c170ac7b4527942b703a0) | `aa39734cbeb5ea14a28c170ac7b4527942b703a0` |
| `hardware/samsung_slsi-linaro/openmax` - [`15ab3081`](https://github.com/LineageOS/android_hardware_samsung_slsi-linaro_openmax/commit/15ab30812af9fe39fff2ae3cd867d7e954c73881) | `15ab30812af9fe39fff2ae3cd867d7e954c73881` |
| `hardware/samsung_slsi/scsc_wifibt/wifi_hal` - [`033d4005`](https://github.com/LineageOS/android_hardware_samsung_slsi_scsc_wifibt_wifi_hal/commit/033d40050c5e23120a5dd0612270cb137a16b300) | `033d40050c5e23120a5dd0612270cb137a16b300` |
| `hardware/samsung_slsi/scsc_wifibt/wpa_supplicant_lib` - [`cc50f101`](https://github.com/LineageOS/android_hardware_samsung_slsi_scsc_wifibt_wpa_supplicant_lib/commit/cc50f101dff4b4480d810e13bea7bee1754cf01d) | `cc50f101dff4b4480d810e13bea7bee1754cf01d` |

### 3.4 Device/product facts discovered in source

The current A51 tree defines:

- `PRODUCT_SHIPPING_API_LEVEL := 29`.
- `PRODUCT_MODEL := SM-A515F`, `PRODUCT_DEVICE := a51`, Samsung brand/manufacturer.
- Build description/fingerprint `A515FXXU5GVK6` (Android 13), while the proprietary lists are primarily from `A515FXXU8HWK1`.
- OTA assert aliases `a51,a51dd,a51nsxx` (verified: `TARGET_OTA_ASSERT_DEVICE`, `device/samsung/a51/BoardConfig.mk:25`); these aliases are not proof that all variants are compatible.
- Optical UDFPS integration, NXP NFC, Exynos camera configuration, AIDL fingerprint work, HWC3/gralloc, Samsung RIL, and legacy HIDL services.

Partition geometry is split across the two BoardConfigs (**v2 correction:** v1 attributed everything to the common tree; the fixed image sizes actually live in the device tree):

| Item | Value | Defined in (verified) |
|---|---:|---|
| Boot image | `61,865,984` bytes; boot header v2; DTB included in boot | `device/samsung/a51/BoardConfig.mk:33` |
| Recovery image | `71,106,560` bytes; full separate recovery image | `device/samsung/a51/BoardConfig.mk:35` |
| DTBO | `8,388,608` bytes; separate DTBO | `device/samsung/a51/BoardConfig.mk:34` |
| Cache | `209,715,200` bytes | `device/samsung/a51/BoardConfig.mk:36` |
| Super | `6,836,715,520` bytes | `BoardConfigCommon.mk:114` |
| Samsung dynamic group | `6,832,521,216` bytes | `BoardConfigCommon.mk:116` |
| Dynamic members | `system`, `system_ext`, `product`, `vendor`, `odm` |
| Filesystems | ext4 for system/system_ext/product; EROFS for vendor/odm; F2FS userdata |
| Boot mode | non-A/B |
| Security/compatibility | vendor patch `2023-08-01`; OTA kernel requirement enforcement currently disabled |

The current fstab uses first-stage logical mounts, a separate metadata partition, F2FS userdata, FBE v2, metadata encryption, and separate boot/recovery/dtbo/vbmeta nodes. Preserve this layout; old A51 TWRP trees must not be used as the geometry or encryption reference.

The common tree reserves 800 MiB for each of system, system_ext, and product under its current no-GMS/reserved-size condition. Audit the exact `WITH_GMS`/`WITHOUT_RESERVED_SIZE` behavior in every build variant rather than guessing from zip size.

### 3.5 Known source conflicts

The common `lineage-24.0` branch is newer in build APIs but does not contain all later semantic fixes present on `lineage-23.2`. Forward-port these changes manually, in this order, resolving each against the Android 17 tree:

1. [`4e1ae02f`](https://github.com/Parbindar7/android_device_samsung_universal9611-common/commit/4e1ae02f) - power hint and cpuctl path refactor.
2. [`e8e2442c`](https://github.com/Parbindar7/android_device_samsung_universal9611-common/commit/e8e2442c) - schedutil up/down transition rate limits.
3. [`c9282400`](https://github.com/Parbindar7/android_device_samsung_universal9611-common/commit/c9282400) - AOSP task-profile/cgroup definitions.
4. [`63f23e12`](https://github.com/Parbindar7/android_device_samsung_universal9611-common/commit/63f23e12) - remove obsolete `/dev/freezer` setup now that the kernel uses cgroup v2 freezer behavior.

Do not solve conflicts by copying the entire 23.2 common history. Android 17 namespace, cgroup, graphics, KeyMint, and release-tool changes must remain visible and reviewable.

## 4. Planned source layout

Create a separate port organization and use a `cnb` branch for every repository that receives a patch. Keep unmodified Lineage dependencies upstream and pin them by SHA in a local manifest.

### 4.1 Required port repositories

Fork or create controlled `cnb` branches for:

```text
device/samsung/a51
device/samsung/universal9611-common
kernel/samsung/universal9611
vendor/samsung/a51
vendor/samsung/universal9611-common
hardware/samsung_slsi-linaro/exynos
hardware/samsung_slsi-linaro/graphics
```

Custom repositories should use full names such as `YOURORG/android_device_samsung_a51` with Evolution's `github-non-los` remote. Do not rely on the default `evo-devices` remote: that remote targets Evolution-X-Devices, where A51 is currently absent.

### 4.2 Local manifest and dependency behavior

Add a local manifest, for example `.repo/local_manifests/a51.xml`, that adds the custom A51/common/kernel/vendor/hardware forks and pins exact revisions. If a path is already present in the cnb/Lineage manifest, remove and re-add it rather than creating duplicate project paths.

Add `evolution.dependencies` to the port tree. Preserve `lineage.dependencies` for Lineage compatibility if desired, but do not assume Evolution roomservice will read it. Every custom dependency must specify its `remote` and exact `revision`; every direct Lineage dependency should be pinned in the local manifest.

After the first successful sync, save:

```bash
repo manifest -r > manifests/a51-evolution-cnb.lock.xml
```

The lockfile, source SHAs, extraction metadata, and patch series are release inputs, not optional notes.

## 5. Execution plan

### Phase 0 - Host and safety preflight

**Goal:** establish a reproducible build and recoverable test device before touching the boot chain.

- Use a Linux x86_64 build host. Chosen strategy: a disposable **Oracle Cloud free-trial VM** (`VM.Standard.E4.Flex` or `E5.Flex`, 16-32 OCPU, 64-128 GB RAM, 700 GB block volume, Ubuntu 22.04/24.04) — roughly $3-7 of the $300 trial credit per 6-hour session — and/or a **foss.crave.io** build account for long-term iteration beyond the 30-day trial window. The pinned manifest and lockfile make hosts disposable by design.
- Follow the [AOSP build requirements](https://source.android.com/docs/setup/start/requirements) and allocate enough SSD space for the full cnb checkout, output trees, proprietary extraction, target-files, and logs. Treat 300-500 GB free storage and 32 GB RAM as practical starting points, then measure the actual tree.
- Install the exact `repo`, Git LFS, Python, Java/Android build prerequisites, host LLVM/Clang dependencies, `avbtool`, sparse-image tools, EROFS tools, `lpdump`, and Samsung Odin/USB recovery tooling on the operator machine.
- Use a sacrificial SM-A515F test handset. Record model, bootloader binary, baseband, Android/One UI version, partition table/PIT, hardware revision, camera SKU, NFC SKU, and SIM configuration.
- Return the handset to the selected stock firmware before each major flashing experiment.
- Unlocking the Samsung bootloader wipes data and trips Knox. Explain this before proceeding; do not promise Knox, Secure Folder, Samsung Pay, or bootloader relocking will work afterward.
- Back up that handset's own `efs` and `cpefs`, and where practical boot/recovery/dtbo/vbmeta/PIT metadata. Store hashes off-device. Never distribute another device's EFS or logs containing IMEI, IMSI, serial, phone number, or MAC addresses.
- Prepare an exact-model Odin rollback package at the same or higher bootloader binary. Samsung rollback protection means that an arbitrary downgrade is not a recovery strategy.

**Exit gate:** stock hardware passes display, touch, cameras, audio, sensors, charging, fingerprint, Wi-Fi/Bluetooth/NFC/GNSS, USB, SIM calls/SMS/data, and the EFS/cpefs backups are readable and hashed.

### Phase 1 - Freeze sources and build metadata

**Goal:** make the future port reproducible before modifying any tree.

- Pin the Evolution manifest to `05755535e93f9e83ebccbda790ccc94102d5abec` and vendor_evolution to `506d2577f439d3d515bdb95ecbeba9821daa1008`.
- Create the controlled `cnb` branches listed in the source matrix, starting from the exact baseline SHAs.
- Add `.repo/local_manifests/a51.xml` and the `evolution.dependencies` graph.
- Sync the repository exactly as documented by Evolution, then save the revision lockfile.
- Record host toolchain versions, kernel compiler version, repo version, Git LFS version, and every environment variable that affects the build.
- Never let a moving branch silently replace a pinned source revision during bring-up.

**Exit gate:** a clean checkout can be recreated from the manifest, local manifest, dependency files, and recorded revisions; no device source is fetched implicitly from an unreviewed remote.

### Phase 2 - Port the product definition and build integration

**Goal:** make `lineage_a51` visible to the Android 17/Evolution build without changing hardware behavior yet.

Critical files to review and port:

```text
device/samsung/a51/AndroidProducts.mk
device/samsung/a51/lineage_a51.mk
device/samsung/a51/device.mk
device/samsung/a51/BoardConfig.mk
device/samsung/a51/lineage.dependencies
device/samsung/a51/configs/
device/samsung/a51/rootdir/
device/samsung/a51/recovery/
device/samsung/a51/releasetools/
device/samsung/a51/sepolicy/
device/samsung/a51/fingerprint/
device/samsung/a51/UdfpsHandler/
```

- Keep `PRODUCT_NAME := lineage_a51`, `PRODUCT_DEVICE := a51`, model `SM-A515F`, shipping API 29, camera variables, UDFPS extension, NFC flags, and OTA assert aliases until hardware evidence justifies a change.
- Ensure the product inherits Evolution's common full-phone configuration through the mapped `vendor/lineage` path exactly once. Avoid duplicate full-phone/GMS inheritance.
- Set `EVO_BUILD_TYPE := Unofficial` in the product/build configuration. Audit Evolution's global fingerprint/spoof configuration and disable any Pixel/Mustang override that would incorrectly describe this Samsung device.
- Verify the expected target is `lineage_a51-cp2a-user` under the cnb release configuration. Do not invent a new product prefix unless the build system proves the existing Lineage-style product cannot be used.
- Preserve the Samsung fingerprint intentionally. Resolve the mismatch between the U8 blob donor and the existing U5 `BuildFingerprint`/`BuildDesc`; do not hide it with a generic Pixel fingerprint.
- Keep A51's `proprietary-files.txt` and extract-utils fixups under source control. Add only documented Android 17 compatibility fixups.

**Exit gate:** `lunch lineage_a51-cp2a-user` resolves, the product graph has no duplicate package/copy rules, and a product configuration dump shows the intended device, partition model, vendor security patch, fingerprint strategy, and unofficial Evolution version.

### Phase 3 - Forward-port the common tree and hardware interfaces

**Goal:** adapt the proven Exynos9611 hardware stack to Android 17 interfaces with narrow, reviewable changes.

Critical common-tree files:

```text
device/samsung/universal9611-common/BoardConfigCommon.mk
device/samsung/universal9611-common/common.mk
device/samsung/universal9611-common/Android.bp
device/samsung/universal9611-common/configs/init/fstab.exynos9611
device/samsung/universal9611-common/configs/init/init.exynos9611.rc
device/samsung/universal9611-common/configs/power/powerhint.json
device/samsung/universal9611-common/manifest.xml
device/samsung/universal9611-common/compatibility_matrix.xml
device/samsung/universal9611-common/releasetools/
device/samsung/universal9611-common/sepolicy/
device/samsung/universal9611-common/extract-files.py
device/samsung/universal9611-common/proprietary-files.txt
```

- Start from common `0fad56be`, not from the older full 23.2 tree.
- Apply the four semantic common-tree changes in the documented order. Resolve path changes in `init.exynos9611.rc`, task profiles, cgroups, power hints, and schedutil nodes against the cnb kernel and Android 17 init behavior.
- Keep `PRODUCT_SOONG_NAMESPACES` changes from common-24; Android 17/cp2a no longer has the same Pixel source namespace assumptions.
- Use Exynos hardware revision `2eea770a`, which carries the KeyMint V5 build migration. Verify final KeyMint/Gatekeeper service declarations against the actual blobs.
- Base graphics on Lineage `lineage-24.0` graphics `703d69fc`. Manually port only the transparent-layer/ignore-layer behavior from `7ee3ed4e`; re-audit every changed HWC2/HWC3 method signature and geometry flag.
- Retain HWC3, gralloc, legacy ION compatibility, Samsung camera variables, Exynos OMX/media integration, display brightness, and the A51 UDFPS gralloc usage bits until compile and hardware tests identify a real incompatibility.
- Reconcile old HIDL services with Android 17 AIDL expectations one service at a time. Do not broadly disable linker namespaces or compatibility checks.
- Port overlays and UDFPS code against the actual cnb `frameworks/base`, SystemUI, Settings, and Evolution surface APIs. Android 17 changes in UDFPS display logic are a likely compile/runtime fault line.

**Exit gate:** device/common/hardware trees compile their individual modules with no permissive SELinux workaround, no blanket `BUILD_BROKEN_*` switch, and no undocumented removal of VINTF/HAL declarations.

### Phase 4 - Kernel and proprietary blob compatibility

**Goal:** prove that the old vendor stack can link and initialize on Android 17 before any flash.

- Inspect the kernel tree's real Makefile version/config; the 23.2 and 24.0 refs point to the same SHA (verified: both branch heads are `1dfd9ef8`) and the Makefile reports Linux **4.14.356** (verified: `VERSION = 4`, `PATCHLEVEL = 14`, `SUBLEVEL = 356`).
- Build the kernel with the cnb Android 17 LLVM/Clang toolchain and the exact `exynos9611-a51_defconfig` target selected by the tree.
- Preserve boot header v2, kernel/ramdisk offsets, DTB-in-boot, separated DTBO, kernel command line, modules, and Samsung device-tree ABI unless measured evidence requires a change.
- Re-extract blobs from the frozen `A515FXXU8HWK1` donor and compare every generated file against the pinned vendor repository.
- Audit pinned exceptions in `proprietary-files.txt`: RIL components from A145F Android 14, Widevine components from P610, VNDK 33 crypto pieces, and other non-A51 material. Verify ABI, licensing, linker namespaces, VINTF declarations, DRM behavior, and radio behavior rather than assuming these substitutions are safe.
- Run ELF dependency checks and resolve missing symbols with narrow blob fixups or shims. Do not solve failures by disabling all namespace isolation.
- Preserve the vendor patch level honestly (`2023-08-01` as currently declared) until a newer, supportable vendor baseline exists.
- Keep SELinux enforcing during testing. Fix denials with correct labels, domains, and narrow permissions; never paste bulk `audit2allow` output.

**Exit gate:** kernel, vendor modules, proprietary services, VINTF manifests/matrices, and device sepolicy pass static checks; every proprietary file has source provenance, hashes, and a donor-firmware note.

### Phase 5 - Build images and audit partitions, AVB, and OTA statically

**Goal:** prove that the artifacts fit the phone before flashing.

Use isolated output trees for every variant. Do not mix Vanilla, mini-GMS, pico-GMS, and full-GMS outputs.

```bash
# Run only after the source port exists.
export OUT_DIR_COMMON_BASE=/path/to/isolated/out
. build/envsetup.sh
lunch lineage_a51-cp2a-user

# Example Vanilla bring-up build.
WITH_GMS=false m evolution
```

Then separately build the selected GMS variant. Full GMS is not accepted merely because compilation completes.

Audit every target-files and OTA output with:

- `unpack_bootimg` or equivalent: header v2, kernel, ramdisk, DTB, command line, offsets, and size.
- `avbtool`: vbmeta descriptors, rollback indexes, key identity, recovery AVB, and absence of development/test keys in release artifacts.
- `lpdump` and logical-partition metadata: super size, group size, logical partition names/extents, and no A/B slot assumptions.
- `simg2img`, ext4 tools, and EROFS tools: filesystem type and unsparsed image size.
- Target-files data: `META/dynamic_partitions_info.txt`, `misc_info.txt`, filesystem configs, VINTF, and image lists.
- OTA ZIP contents: `IMAGES/boot.img`, `recovery.img`, `dtbo.img`, `vbmeta.img`, logical images, `android-info.txt`, metadata, and updater script.

Hard limits:

```text
boot       <= 61,865,984 bytes
recovery   <= 71,106,560 bytes
dtbo       <=  8,388,608 bytes
super      <= 6,836,715,520 bytes
dynamic    <= 6,832,521,216 bytes
```

The sum of unsparsed logical images plus required metadata/reserved space must fit the fixed dynamic group. Never enlarge these values beyond the stock GPT/PIT geometry to make a build pass.

The generated OTA must merge the device's One UI 5/bootloader assertion with both DTBO and vbmeta installation. The device currently overrides `TARGET_RELEASETOOLS_EXTENSIONS` and explicitly adds DTBO, while the common extension adds DTBO and vbmeta. Consolidate this into one final extension and inspect the generated updater script so each image is written exactly once and boot is not accidentally omitted.

**Verified 2026-08-05 — this defect is real, not hypothetical.** `device/samsung/a51/BoardConfig.mk:30` sets `TARGET_RELEASETOOLS_EXTENSIONS := $(DEVICE_PATH)/releasetools`; the device `releasetools.py` adds only `dtbo.img` plus the OneUI 5 bootloader assertion (`a51.verify_bootloader_min`), while the masked common `releasetools.py` adds both `dtbo.img` and `vbmeta.img`. As shipped, an OTA built from these trees would never write `vbmeta`. Fixing this consolidation is a mandatory Phase 2/5 work item.

The current common BoardConfig points recovery AVB at AOSP's test RSA key (verified: `BoardConfigCommon.mk:192`, `BOARD_AVB_RECOVERY_KEY_PATH := external/avb/test/data/testkey_rsa4096.pem`; vbmeta itself is built with `--algorithm NONE --flags 0`). That may be acceptable only for controlled development experiments. A release package must use controlled release keys and a documented AVB/signing process.

Required build sequence:

1. Compile individual affected modules to shorten feedback loops.
2. Build kernel, recovery, boot, dtbo, and vbmeta.
3. Build `target-files-package` and OTA tools.
4. Run VINTF, sepolicy, ELF, AVB, image-size, and logical-partition audits.
5. Produce a full OTA with hashes.
6. Repeat from a clean output tree.
7. Build the selected GMS variant in a different output tree and repeat every audit.

**Exit gate:** clean Vanilla and GMS target-files/OTA artifacts fit the fixed partition geometry, pass AVB/VINTF/static checks, reject wrong model/firmware assertions, and have complete hashes plus a revision lockfile.

### Phase 6 - Recovery-only bring-up

**Goal:** prove the boot chain and recovery can safely prepare userdata without writing the system partition.

- Restore the exact stock baseline, then flash only the minimum tested recovery/boot-chain artifact using a verified Samsung/Odin procedure.
- Test three consecutive recovery boots before attempting a ROM installation.
- Verify display, touch/buttons, USB gadget, ADB authorization, `adb sideload`, reboot targets, log retrieval, dynamic-partition metadata access, metadata/cache mounts, and signed-package verification.
- Verify recovery can format userdata as F2FS and recreate Android 17-compatible metadata/FBE state.
- Confirm model and bootloader assertions fail safely before any partition write.
- Capture recovery logs and pstore/ramoops after every failed boot.
- Do not require TWRP-style browsing of decrypted userdata. The release recovery must reliably format data, install the ROM, preserve update metadata, and report errors.

**Stop condition:** any recovery, AVB, DTB, DTBO, USB, or init failure blocks system-image flashing. Do not diagnose a boot-chain failure by repeatedly overwriting `super`.

### Phase 7 - First clean installation and encrypted boot

**Goal:** obtain the first reproducible Android 17 boot while preserving recoverability.

- Return to the exact stock baseline and use the validated recovery.
- Format data from recovery; start with a full OTA, not an incremental update.
- Save the complete recovery install log, early kernel log, logcat, pstore/ramoops, and OTA verification output.
- Classify the failure point before changing code:
  - no kernel/recovery: boot image, AVB, DTB, or DTBO;
  - kernel but no mounts: super metadata, fstab, or logical partitions;
  - boot animation loop: system server, HAL, VINTF, linker, or SELinux;
  - setup/lockscreen crash: overlay, UDFPS, framework, or service integration.
- Verify `sys.boot_completed=1`, correct logical mounts, ext4/EROFS/F2FS types, FBE v2, metadata encryption, and enforcing SELinux.
- Set a PIN, populate representative user data, cold reboot at least five times, unlock, and verify device-encrypted storage before unlock and credential-encrypted storage after unlock.
- Test Android and recovery factory-reset paths.

**Exit gate:** five cold boots and PIN unlocks succeed without repeating `vold`, KeyMint, Gatekeeper, or init failures; no critical service crash loop remains.

### Phase 8 - SELinux, VINTF, and vendor compatibility

**Goal:** turn a first boot into a correctly integrated Android 17 system.

- Run `checkvintf`, framework/device compatibility checks, and the relevant Treble/VTS tests.
- Compare declared HALs with running binder/HIDL/AIDL services using service listings, `lshal` where available, and init status.
- Investigate every repeating crash, tombstone, linker error, or AVC denial.
- Keep `getenforce` at `Enforcing`. Add labels/domains/allow rules only where the access is valid and narrowly scoped.
- Re-evaluate `PRODUCT_OTA_ENFORCE_VINTF_KERNEL_REQUIREMENTS := false`; document why it exists and the release/security consequence if it cannot be removed.
- Document every legacy compatibility exception caused by the old kernel or vendor stack.
- Do not delete manifest entries or disable neverallows merely to make tests green.

**Exit gate:** VINTF checks pass or every unavoidable exception is documented and accepted; there is no repeating critical-service crash or recurring AVC during a full smoke test.

### Phase 9 - Hardware bring-up matrix

Test one hardware area at a time and save logs/results.

| Area | Required checks |
|---|---|
| Display/touch/graphics | Boot animation, brightness range, rotation, doze/AOD, multitouch/edges, HWC3/gralloc, GLES/Vulkan, HWUI, screenshots, video playback, sustained rendering, no fence/compositor crash. |
| Storage/USB | Internal storage, SD, USB OTG, MTP, ADB, USB tethering, quota/casefold, low-space handling, copy/hash integrity, reboot after filling storage. |
| RIL/baseband | IMEI retained, baseband, SIM PIN, supported single/dual-SIM behavior, registration, calls where the carrier supports circuit-switched fallback, SMS/MMS, LTE data, APNs, airplane toggle, reboot/handover. |
| Audio | Speaker, earpiece, all microphones, recorder, alarm, wired headset/mic/buttons, USB audio, Bluetooth A2DP/HFP, in-call routing, volume, and relevant mixer variants. |
| Wi-Fi/Bluetooth | 2.4/5 GHz, WPA2/WPA3, hotspot, Wi-Fi Direct, randomized MAC, suspend/reconnect, Bluetooth classic/LE, A2DP/HFP, and coexistence. |
| NFC/GNSS | Correct NFC SKU, tag/HCE behavior where supported, repeated toggle, cold/warm GPS fixes, navigation, airplane/reboot behavior. |
| UDFPS/security | AIDL fingerprint service, optical HBM, overlay coordinates, enrollment, lockscreen/AOD/screen-off auth, lockout, reboot auth, brightness and Night Display/Extra Dim interactions. |
| Camera/media | Main, ultrawide, macro, depth-assisted, and front cameras; flash/torch, autofocus, photo/video modes, playback, third-party camera, QR, repeated open/close, no provider tombstones. |
| Sensors/power | Proximity, light, rotation, gyro, compass, steps, vibration, charging/fast charge, battery reporting, suspend/deep sleep, thermal throttling, and wake behavior. |

Treat RIL and IMS separately. A working `rild`, SIM registration, and LTE data do not prove VoLTE or VoWiFi. The public A51 stack has no complete Samsung IMS implementation; do not advertise IMS voice until proprietary IMS services, framework integration, carrier configuration, permissions, SELinux, and multi-carrier testing exist.

**Exit gate:** every supported feature has an evidence-backed pass/fail status, and unsupported features are stated explicitly rather than hidden.

### Phase 10 - OTA, endurance, rollback, and release

**Goal:** prove that the build is maintainable and recoverable, not merely bootable once.

- Install build N, configure a PIN and representative data, then apply build N+1 through the intended non-A/B OTA path.
- Verify applications, userdata, FBE keys, baseband, DTBO, vbmeta, and all logical partitions survive.
- Ship full OTAs until incremental packages pass at least two consecutive upgrade paths.
- Test corrupted/truncated package rejection before writes.
- Run at least 20 cold boots, repeated recovery boots/sideloads, a 72-hour daily-use soak, overnight deep sleep, charge/discharge and thermal cycles, and repeated camera/call/Wi-Fi/Bluetooth/GNSS cycles.
- Document that non-A/B devices lack an inactive slot or automatic rollback. An interrupted update can leave the active install unbootable.
- Default custom-ROM downgrades to a clean flash/wipe unless data compatibility is proven.
- Restore stock only with exact-model Odin BL/AP/CP/CSC at the same or higher bootloader binary.
- Never relock the bootloader while custom images remain installed; Knox remains tripped.

Release only when:

- Recovery, clean install, encrypted boot, update, factory reset, and stock rollback are proven.
- SELinux is enforcing and VINTF checks pass, or every unavoidable exception is explicitly documented and accepted.
- No P0 issue exists: brick risk, EFS/IMEI damage, data loss, encryption failure, or boot failure.
- No unresolved P1 issue remains in display/touch, supported voice/SMS/data, audio, main camera, Wi-Fi, Bluetooth, fingerprint, charging, or suspend.
- Release keys replace development/test keys; all artifacts have SHA-256 hashes and pinned source revisions.
- Kernel-source and proprietary-license obligations are documented; proprietary blobs are not redistributed without permission.
- Security patch reporting is truthful. Do not hide the `2023-08-01` vendor level or the legacy 4.14.x kernel.
- Release notes state exact SM-A515F scope, firmware prerequisite, mandatory data wipe, non-A/B OTA risk, bootloader/Knox consequences, unsupported IMS/Samsung features, and rollback procedure.
- The build remains unofficial until Evolution X approves device status, signing, and OTA infrastructure.

**Exit gate:** clean install, N-to-N+1 update, factory reset, full stock restore, and endurance testing all succeed with no kernel panic, pstore crash, EFS change, data corruption, or repeating HAL crash.

## 6. Risk register and stop conditions

| Risk | Severity | Mitigation / evidence required |
|---|---:|---|
| No public Android 17 A51 boot proof | P0 | Treat every branch label as unproven until recovery and clean-boot evidence exists. |
| Legacy 4.14.x kernel and old vendor target/VINTF stack | P0/P1 | Keep enforcement on, run VINTF/VTS checks, document exceptions, and avoid security claims beyond evidence. |
| Mixed blob provenance (U8 A51 plus A145F/P610/VNDK material) | P0/P1 | Re-extract, hash, inspect ELF/VINTF/linker dependencies, and test RIL/DRM/camera/attestation on hardware. |
| Product fingerprint does not match blob donor | P1 | Freeze a truthful device fingerprint strategy; do not use a Pixel spoof as a blanket fix. |
| Full GMS overflows the dynamic group | P1 | Build Vanilla/mini/full separately; inspect `dynamic_partitions_info.txt`, image sizes, and group extents before flashing. |
| Device releasetools masks common vbmeta handling | P0 | Merge assertion, DTBO, and vbmeta logic in one extension; inspect the generated updater script. |
| Android 17 FBE/metadata behavior differs | P0 | Recovery-only format tests, encrypted cold boots, reset tests, and vold/KeyMint logs. |
| HWC3/graphics transparent-layer patch conflicts | P1 | Base on Lineage-24 graphics and manually port the narrow patch; run SurfaceFlinger and visual tests. |
| UDFPS overlay/HBM/API regressions | P1 | Port against actual cnb SystemUI/framework APIs and run enrollment/AOD/screen-off/brightness tests. |
| Samsung IMS absent | P1 | Do not advertise VoLTE/VoWiFi; treat IMS as a separate project. |
| Wrong variant or unsupported firmware flashed | P0 | Tight OTA asserts, exact firmware prerequisite, sacrificial device, and proven Odin rollback package. |
| Non-A/B update interruption | P0 | Full OTA first, corruption tests, no assumption of automatic rollback, and a proven stock recovery path. |

Stop immediately and restore stock if any experiment causes unknown IMEI/baseband, EFS/cpefs change, persistent AVB failure, uncontrolled data loss, or a bootloader state that cannot be recovered with the prepared exact-model package.

## 7. Required evidence and artifacts

Store these outside the source tree or in a private release archive:

1. Hardware/support matrix and exact stock firmware identifiers.
2. EFS/cpefs backup hashes, never public contents.
3. Source manifest lockfile and every fork/direct-dependency SHA.
4. Patch series with conflict rationale for common, graphics, KeyMint, UDFPS, sepolicy, and release tools.
5. Proprietary extraction donor version, file list, fixups, hashes, and licensing notes.
6. Kernel/build toolchain versions and clean-build logs.
7. Boot/recovery/DTBO/vbmeta image-size and AVB reports.
8. `lpdump`/dynamic-partition metadata and filesystem reports.
9. Target-files/OTA ZIP file list, updater script, assertions, and signing report.
10. Recovery install logs, early-boot logs, pstore/ramoops, VINTF output, SELinux status, and crash/tombstone triage.
11. Hardware test matrix with carrier/SIM details redacted and reproducible steps.
12. N-to-N+1 OTA, factory-reset, endurance, and stock-rollback records.

## 8. Definition of done

A successful compile is not a completed port.

The port is ready for internal testing only when recovery, clean install, encrypted first boot, enforcing SELinux, basic display/touch/storage, and stock rollback are proven.

The port is release-ready only when all Phase 10 gates pass and the release documentation states every known limitation. Until then, artifacts should be labeled development-only and should not be distributed as a daily-driver ROM.

## 9. Recommended next action after approval

Do not begin by hand-editing trees. The Phase 1 inputs are now drafted in `port-kit/`:

1. `port-kit/local_manifests/a51.xml` — bootstrap local manifest with **all 16 repositories pinned to the exact verified SHAs** (7 port repos + 9 Lineage SLSI dependencies). Works immediately against the public baselines; a commented block shows how to swap each port repo to your controlled fork.
2. `port-kit/evolution.dependencies` — roomservice dependency graph for the `device/samsung/a51` fork, schema-matched to Evolution's `roomservice.py` (`repository` / `target_path` / `remote` / `revision`).
3. `port-kit/01-create-forks.sh` — `gh` CLI script that forks the 7 port repositories into a controlled org and creates `cnb` branches at the pinned baseline SHAs.

Sequence: provision the build host → run `01-create-forks.sh` → swap the manifest to the forks → freeze the SM-A515F stock baseline → sync → `lunch lineage_a51-cp2a-user` smoke test (Phase 2). Only after those inputs are reviewed should the Android 17 compile phase begin.

## 10. Research sources

- [Evolution X manifest](https://github.com/Evolution-X/manifest)
- [Evolution X cnb manifest commit](https://github.com/Evolution-X/manifest/commit/05755535e93f9e83ebccbda790ccc94102d5abec)
- [Evolution X vendor configuration](https://github.com/Evolution-X/vendor_evolution/commit/506d2577f439d3d515bdb95ecbeba9821daa1008)
- [Evolution X roomservice](https://github.com/Evolution-X/vendor_evolution/blob/cnb/build/tools/roomservice.py)
- [Parbindar7 A51 device tree](https://github.com/Parbindar7/android_device_samsung_a51/tree/lineage-23.2)
- [Parbindar7 universal9611 common tree](https://github.com/Parbindar7/android_device_samsung_universal9611-common/tree/lineage-24.0)
- [Parbindar7 universal9611 kernel](https://github.com/Parbindar7/android_kernel_samsung_universal9611/tree/lineage-24.0)
- [Parbindar7 A51 vendor tree](https://github.com/Parbindar7/android_vendor_samsung_a51/tree/lineage-23.2)
- [Parbindar7 universal9611 vendor tree](https://github.com/Parbindar7/android_vendor_samsung_universal9611-common/tree/lineage-23.2)
- [LineageOS Samsung SLSI graphics base](https://github.com/LineageOS/android_hardware_samsung_slsi-linaro_graphics/tree/lineage-24.0)
- [AOSP build requirements](https://source.android.com/docs/setup/start/requirements)

## Appendix A - Verification log (2026-08-05)

Independent line-by-line verification against live GitHub sources. Roughly 30 checks; result classes: ✅ confirmed exactly, 🔧 corrected in v2.

| # | Claim | Result |
|---|---|---|
| 1 | All 9 baseline commit SHAs (§3.2) exist | ✅ 9/9 via GitHub API |
| 2 | `cnb` `default.xml`: AOSP `android-17.0.0_r1`, default `refs/heads/lineage-24.0` | ✅ byte-exact |
| 3 | `version.mk`: `PRODUCT_VERSION_MAJOR = 17`, `EVO_VERSION_BASE := 12.1`, build type Official/Unofficial only | ✅ exact |
| 4 | README build commands (`repo init -b cnb --git-lfs` … `lunch lineage_codename-cp2a-user` … `m evolution`) | ✅ verbatim (file is `README.mkdn`) |
| 5 | Roomservice reads `evolution.dependencies`; schema `repository`/`target_path`/`remote` (default `evo-devices`)/`revision`\|`branch` | ✅ `roomservice.py:233-236, 277` |
| 6 | `github-non-los` remote exists, `fetch="https://github.com"` | ✅ `snippets/evolution.xml` |
| 7 | Partition sizes: boot 61,865,984 / recovery 71,106,560 / dtbo 8,388,608 / cache 209,715,200 / super 6,836,715,520 / group 6,832,521,216 | ✅ byte-exact; 🔧 attribution split corrected (device vs common BoardConfig) |
| 8 | Filesystems ext4 (system/system_ext/product), EROFS (vendor/odm), F2FS userdata; 800 MiB reserved ×3 | ✅ `BoardConfigCommon.mk:132-143` |
| 9 | Kernel Linux 4.14.x; lineage-23.2 and lineage-24.0 heads identical | ✅ 4.14.**356**; both heads `1dfd9ef8` |
| 10 | Four forward-port commits (`4e1ae02f`, `e8e2442c`, `c9282400`, `63f23e12`) exist with described content | ✅ commit messages match descriptions |
| 11 | `PRODUCT_NAME lineage_a51`, `SM-A515F`, shipping API 29, fingerprint `A515FXXU5GVK6` (A13) | ✅ `lineage_a51.mk:30-44` |
| 12 | Donor firmware `A515FXXU8HWK1` | ✅ `proprietary-files.txt` header |
| 13 | `board-info.txt` requires bootloader token G | ✅ `require version-bootloader-min=G` |
| 14 | Vendor security patch `2023-08-01` | ✅ `BoardConfigCommon.mk:171` |
| 15 | OTA assert aliases `a51,a51dd,a51nsxx` | ✅ `BoardConfig.mk:25` |
| 16 | Recovery AVB uses AOSP test key | ✅ `BoardConfigCommon.mk:192` (`testkey_rsa4096.pem`) |
| 17 | Releasetools conflict: device masks common vbmeta write | ✅ confirmed in both `releasetools.py` files — real defect |
| 18 | Lineage SLSI dependency SHAs (§3.3) | ✅ spot-checked 3/9 valid (sepolicy, hardware/samsung, graphics) |
| 19 | `WITH_GMS` defaults to `true` | 🔧 **wrong** — no default exists at `506d2577`; unset fires neither branch. Corrected in §2/§3.1. |
| 20 | A51 absent from Evolution-X-Devices | ✅ consistent (no official A51 device repo found; org layout prevents exhaustive proof) |

