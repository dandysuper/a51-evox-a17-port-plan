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

The public script:

- runs only as a normal `crave run` build job, never in a devspace or
  `crave ssh`;
- initializes the Evolution X manifest with `--depth 1`;
- uses `/opt/crave/resync.sh` as documented by the Crave unsupported-ROM guide;
- does not use `rm -rf`, `make clean`, `rm -rf out`, `--clean`, or create a
  second Android source directory;
- builds one device target only; and
- keeps `WITH_GMS=false` explicit before lunch.

The previous job `292024` referenced a local-only copy of the script and ended
with exit code 130 before producing source-sync output or artifacts. The public
script in this repository supersedes that copy.

## Running it

Wait for a Crave moderator to confirm an Android 17 carrier project. After that
approval, invoke the script from this public repository with a normal
`crave run --no-patch` job. Pin the raw URL to a reviewed commit rather than an
unversioned branch when submitting the actual build.

## Safety

Samsung bootloader unlocking wipes user data and permanently trips Knox.
Flashing unverified images can cause data loss or an unbootable device. Use a
test SM-A515F, preserve its own EFS/cpefs backups privately, and maintain a
verified same-or-newer-bootloader Odin recovery package. A successful compile
is not permission to flash: partition sizing, AVB, recovery, and boot-chain
gates in the plan must be completed first.
