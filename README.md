# Samsung Galaxy A51 Evolution X 12.1 / Android 17 Port

Public research, planning, and Crave build-bootstrap files for an unofficial
Evolution X 12.1 (Android 17) forward-port to the Samsung Galaxy A51 4G
(`SM-A515F`, `a51`).

## Current status

The port remains experimental and has not produced a verified bootable build.
The Crave build script is published here so moderators and other contributors
can inspect it. **Do not queue it yet:** an approved Android 17 Crave carrier
project has not been identified.

Crave project 82 is named PixelOS, but its public `seventeen` manifest currently
selects AOSP `android-16.0.0_r4`, PixelOS `sixteen-qpr2`, and LineageOS
`lineage-23.2`. Evolution X `cnb` selects AOSP `android-17.0.0_r1` and LineageOS
`lineage-24.0`, so project 82 is not presently a verified same-generation
carrier.

## Files

- [Detailed port plan](A51_EVOX_A17_PORT_PLAN_v2.md)
- [Open Crave build script](crave-sync-build.sh)
- [Pinned A51 local manifest](local_manifests/a51.xml)

The local manifest contains public GitHub sources only. It does not contain
proprietary firmware, credentials, signing keys, or private repository URLs.

## Crave policy notes

The script is an aggressive, resilient port of the orchestration that produced
the successful Crave job
[`292073`](https://foss.crave.io/app/#/build/info/292073?team=14) (Xiaomi
`chime` Evolution X 17, `snuffles198/android-builds` `remote/evox-17.sh`),
adapted to the Samsung Galaxy A51 (`lineage_a51`). Build-292073 techniques
preserved:

- **stale-manifest wipe** — `.repo/manifests*` is removed before `repo init`,
  so a reused LOS22/CipherOS/PixelOS carrier workspace cannot poison the
  Evolution tree (this is exactly what broke job `292171`);
- **double Crave resync** — `/opt/crave/resync.sh` runs twice; the second pass
  must fully succeed and is gated by `check_fail`;
- **whole-tree deep clean** — `repo forall -c "git clean -fdx ; git reset
  --hard HEAD"` between the two resyncs;
- **Soong OOM retry ladder** — `GOMEMLIMIT`/`GOGC`/`GOMAXPROCS` tiers with
  `rm -rf out/soong` between attempts and a 30-minute `soong_build` watchdog,
  followed by the real `m evolution` build;
- **soft-fail vs hard-fail classification** — `check_fail` reports `softfail`
  if a zip already exists, otherwise `fail`, and never uses private signing
  keys (this port performs no signing/download/OTA publishing).

This port deliberately keeps a single pinned local manifest
(`local_manifests/a51.xml`, 16 projects pinned by exact SHA) and stays vanilla:
`WITH_GMS=false` is exported before lunch because the pinned Evolution vendor
has **no default** for `WITH_GMS`.

The script still:

- runs only as a normal `crave run` build job unless `ALLOW_DEVSPACE=1`;
- uses `/opt/crave/resync.sh` as documented by the Crave unsupported-ROM guide;
- builds one device target only, then asserts `TARGET_PRODUCT == lineage_a51`;
- writes the build log, manifest lockfile, local-manifest copy, and host
  metadata under `a51-build-artifacts/` so Crave can collect them.

Job history: `292024` ended with exit 130 (interrupted) before sync output;
`292171` failed because the reused LOS22 workspace retained its old project set
and `resync.sh` continued after the manifest-sync error. The current script
removes stale carrier manifests and local manifests *before* init/sync, so a
dirty workspace is rebuilt in place instead of being carried forward.

## Running it

Wait for a Crave moderator to confirm an Android 17 carrier project. When
submitting, choose the newest approved LineageOS/A17 project and its largest
available Linux build platform (for example, a current `linux32` box if the
team exposes one). The worker script cannot change a project's platform; the
project selected by `crave run` controls that. The script defaults its build
parallelism to the worker's reported CPU count, with `BUILD_JOBS` available for
an explicit lower value if memory pressure requires it.

Invoke the script from this public repository with a normal `crave run
--no-patch` job. Configure the project artifact patterns to collect
`a51-build-artifacts/**` and the final files under
`out/target/product/a51/` before submitting. Pin the raw URL to a reviewed
commit rather than an unversioned branch when submitting the actual build.

## Safety

Samsung bootloader unlocking wipes user data and permanently trips Knox.
Flashing unverified images can cause data loss or an unbootable device. Use a
test SM-A515F, preserve its own EFS/cpefs backups privately, and maintain a
verified same-or-newer-bootloader Odin recovery package. A successful compile
is not permission to flash: partition sizing, AVB, recovery, and boot-chain
gates in the plan must be completed first.
