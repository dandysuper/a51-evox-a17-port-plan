# Samsung Galaxy A51 Evolution X 12.1 / Android 17 Port Plan

Research and implementation planning for an unofficial Evolution X 12.1
(Android 17) forward-port to the Samsung Galaxy A51 4G (`SM-A515F`, `a51`).

## Plan

- [A51_EVOX_A17_PORT_PLAN_v2.md](A51_EVOX_A17_PORT_PLAN_v2.md)

The document contains the pinned source matrix, porting sequence, build-host
requirements, partition and OTA constraints, recovery-first bring-up process,
hardware test matrix, risk register, and release gates.

## Status

This repository contains the plan only. It does not contain ROM source,
proprietary blobs, build artifacts, recovery images, or the referenced private
`port-kit` working files. No complete public Android 17 boot proof currently
exists for this device, so the work remains experimental and unofficial.

## Safety

Samsung bootloader unlocking wipes user data and permanently trips Knox.
Flashing unverified images can cause data loss or an unbootable device. Use a
test SM-A515F, preserve its own EFS/cpefs backups privately, and maintain a
verified same-or-newer-bootloader Odin recovery package.
