# Samsung Galaxy A51 — Evolution X 12.1 / Android 17

Public research, patches, and build bootstrap for an unofficial Evolution X 12.1
(Android 17) forward-port to the Galaxy A51 4G (`SM-A515F`, `a51`, Exynos 9611).

## Status

Experimental. No verified bootable build yet.

As of August 2026 no device tree for **any** Exynos 9611 device — a51, m21, m31,
m31s, f41 — exists on an Android 17 branch. The common tree and kernel do:
`universal9611-common` and `kernel_samsung_universal9611` both carry
`lineage-24.0`, and the kernel has real Android 17 work in it (a bpf-5.10
backport, cgroup v2 freezer, the SchedTune-to-uclamp migration). The
device-specific layer is unstarted, which is what this repository is for.

The `lineage-24.0` common tree is a fast-forward of `lineage-23.2` plus five
commits touching four files. It imposes no requirements on the device tree.

## Files

- [Port plan](A51_EVOX_A17_PORT_PLAN_v2.md) — research and phased implementation plan
- [Build script](crave-sync-build.sh) — syncs, patches, builds; one command
- [Local manifest](local_manifests/a51.xml) — pinned, public sources only
- [Device tree patches](patches/device_samsung_a51/) — four patches with rationale

## Building

Submitted as a detached remote Crave batch job. Devspace is used only for
inspection, workspace setup and persistence — never for `repo sync`, Soong, or
the build itself.

```bash
crave run --projectID <project> --detached --no-patch -- \
  "curl -fsSL https://raw.githubusercontent.com/dandysuper/a51-evox-a17-port-plan/<commit>/crave-sync-build.sh | bash"
```

The job runs on the Crave worker and survives the local terminal disconnecting.
Job `292024` exited 130 because it was not detached and the submitting machine
dropped — a client-side disconnect, not a build failure and not a moderator
action.

Pin the raw URL to a reviewed commit, never `main`. A queued job fetches an
immutable commit, so pushing new patches does not affect a job already in the
queue; changing what a queued job runs means stopping it and submitting exactly
one replacement.

The script re-initialises the workspace onto the Evolution X `cnb` manifest and
removes the carrier project's stale manifest state, so the underlying project's
own ROM configuration does not matter. Job `292171` failed before compilation
precisely because that stale state survived — `revision refs/heads/master in
manifests not found`, then a missing `device/qcom/sepolicy_vndr/sm8650`.

Check the project's `artifactPatterns` covers `*.zip` and `*.img`, or the output
will not be collected.

## Crave compliance

- runs only as a normal `crave run` job, never in a devspace or `crave ssh`
- `/opt/crave/resync.sh` for syncing; never a bare `repo sync`
- `repo init --depth 1`, with a preflight that warns if a pinned SHA is no
  longer its branch tip
- no `rm -rf`, no `make clean`, no `--clean`, no second source directory
- one device target
- `WITH_GMS=false` set explicitly — there is no upstream default
- public GitHub sources only; no credentials, keys, or private repositories
- patch application is idempotent, so re-runs do not need a clean tree

## Patches

Four patches against `device/samsung/a51` at `b9b86945`. Three are defects in
the current `lineage-23.2` tree, independent of the Android 17 port:

| | |
|---|---|
| 0001 | OTAs never wrote `vbmeta.img` — the device releasetools masked the common one |
| 0002 | Declared super partition is 454 MB larger than SM-A515F hardware |
| 0003 | `soong_config_set` silently truncated the camera ID list to a single entry |
| 0004 | Dangling reference to a deleted public sepolicy directory |

Rationale, line numbers, and the open questions the patches do *not* address are
in [patches/device_samsung_a51/README.md](patches/device_samsung_a51/README.md).

## Safety

Unlocking a Samsung bootloader wipes user data and permanently trips Knox.
Flashing unverified images can leave a device unbootable. Use a test SM-A515F,
keep its EFS/cpefs backups private, and have a verified Odin package at the same
or newer bootloader before flashing anything.

A successful compile is not permission to flash. The partition sizing, AVB,
recovery, and boot-chain gates in the port plan come first.
