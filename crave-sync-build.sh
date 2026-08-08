#!/usr/bin/env bash
# =============================================================================
# A51 (SM-A515F) — Evolution X 12.1 / Android 17 — aggressive Crave build script
# -----------------------------------------------------------------------------
# Orchestration ported 1:1 from the successful Crave job 292073:
#   https://raw.githubusercontent.com/snuffles198/android-builds/refs/heads/main/remote/evox-17.sh
#
# Why this script is resilient (build-292073 method):
#   1. wipe the stale carrier manifest (.repo/manifests*) before `repo init`,
#      so a reused LOS22/CipherOS workspace cannot poison the Evolution tree
#      (this is the exact bug that killed job 292171);
#   2. remove pre-existing local manifests, then install ONLY the pinned A51
#      local manifest (all 16 device/vendor/hardware/kernel projects pinned);
#   3. deep-clean every managed project:
#        repo forall -c "git clean -fdx ; git reset --hard HEAD"
#   4. run resync twice via resync_with_pruning(), which retries and prunes
#      obsolete carrier projects repo cannot remove; second pass must succeed;
#   5. Soong OOM workaround: GOMEMLIMIT/GOGC retry ladder with `rm -rf
#      out/soong` between attempts and a 30-minute soong_build watchdog;
#   6. check_fail() soft/hard failure classification (zip exists => softfail);
#   7. optional Telegram/ntfy notifications that never break the build.
#
# Target   : lineage_a51-cp2a-user   (vanilla, WITH_GMS=false)
# Output   : out/target/product/a51/EvolutionX*.zip
# Artifacts: a51-build-artifacts/{build.log,lockfile.xml,build-metadata.txt}
#
# Submit (from the matching Crave checkout):
#   crave run --projectID <approved-A17-project> --detached --no-patch -- \
#     "/usr/bin/curl -fsSL -o builder.sh <raw-url-of-this-script> && \
#      A51_PUBLIC_REVISION=<reviewed-commit> /usr/bin/bash builder.sh"
#
# Env knobs (all optional):
#   A51_PUBLIC_REPO_RAW / A51_PUBLIC_REVISION   source of local_manifests/a51.xml
#   EVO_MANIFEST_SHA                            pin Evolution manifest
#                                               (default: cnb tip, like 292073)
#   BUILD_JOBS                                  parallelism (default: nproc --all)
#   CRAVE_SOONG_WORKAROUND                      0/1 (default 1)
#   ALLOW_DEVSPACE                              set to 1 to permit devspace runs
# =============================================================================

set -o pipefail

# --- optional secrets / environment (must never abort) ------------------------
for _env_file in \
  "$HOME/android-builds/dev-secrets/telegram.sh" \
  "$HOME/android-builds/dev-secrets/secrets.sh" \
  "$HOME/android-builds/dev-secrets/ntfy.sh" \
  /tmp/crave_bashrc
do
  [[ -f "$_env_file" ]] && source "$_env_file" || true
done
unset _env_file

if [[ "${DCDEVSPACE:-0}" == "1" || "$(pwd -P)" == /crave-devspaces* ]]; then
  if [[ "${ALLOW_DEVSPACE:-0}" != "1" ]]; then
    echo "REFUSING: run as a normal 'crave run' build job, not a devspace." >&2
    exit 64
  fi
  echo "WARNING: running inside a devspace (ALLOW_DEVSPACE=1). Not a guaranteed path."
fi

set -u

# --- configuration ------------------------------------------------------------
ANDROID_ROOT="${ANDROID_ROOT:-/tmp/src/android}"
DEVICE="${DEVICE:-a51}"
PACKAGE_NAME="${PACKAGE_NAME:-EvolutionX}"
BUILD_JOBS="${BUILD_JOBS:-$(nproc --all)}"
EVO_MANIFEST_SHA="${EVO_MANIFEST_SHA:-}"
PUBLIC_REPO_RAW="${A51_PUBLIC_REPO_RAW:-https://raw.githubusercontent.com/dandysuper/a51-evox-a17-port-plan}"
PUBLIC_REVISION="${A51_PUBLIC_REVISION:-main}"
A51_MANIFEST_URL="${PUBLIC_REPO_RAW}/${PUBLIC_REVISION}/local_manifests/a51.xml"
ARTIFACT_DIR="${ANDROID_ROOT}/a51-build-artifacts"
export TZ="${TZ:-UTC}"

# --- workspace bootstrap (build-292073 technique) -----------------------------
mkdir -p /tmp/src
if [[ ! -d "${ANDROID_ROOT}" || -L "${ANDROID_ROOT}" ]]; then
  if [[ "$(pwd)" != "${ANDROID_ROOT}" ]]; then
    rm -rf "${ANDROID_ROOT}"
    ln -s "$PWD" "${ANDROID_ROOT}"
  fi
fi
cd "${ANDROID_ROOT}"

if [[ ! -x /opt/crave/resync.sh ]]; then
  echo "REFUSING: /opt/crave/resync.sh is unavailable (not a Crave build worker)." >&2
  exit 66
fi

mkdir -p "${ARTIFACT_DIR}"
exec > >(tee -a "${ARTIFACT_DIR}/build.log") 2>&1

SECONDS=0

notify_send() {
  local message
  message="$* - $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo "[notify] ${message}"
  if [[ -n "${TG_TOKEN:-}" && -n "${TG_CID:-}" ]]; then
    curl -s --max-time 20 -X POST \
      "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
      -d chat_id="${TG_CID}" -d text="${message}" >/dev/null 2>&1 || true
  fi
  if [[ -n "${NTFYSUB:-}" ]]; then
    curl -s --max-time 20 -d "${message}" "https://ntfy.sh/${NTFYSUB}" >/dev/null 2>&1 || true
  fi
}

check_fail() {
  local status=$?
  if [[ ${status} -ne 0 ]]; then
    if ls out/target/product/${DEVICE}/${PACKAGE_NAME}*.zip >/dev/null 2>&1; then
      notify_send "Build ${PACKAGE_NAME} ${DEVICE} on crave.io SOFTFAILED (zip exists)."
      echo "softfail" > result.txt
    else
      notify_send "Build ${PACKAGE_NAME} ${DEVICE} on crave.io FAILED."
      if [[ -f out/error.log && -n "${TG_TOKEN:-}" && -n "${TG_CID:-}" ]]; then
        curl -s --max-time 30 -L -F document=@"out/error.log" \
          -F caption="error log" -F chat_id="${TG_CID}" \
          -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendDocument" \
          >/dev/null 2>&1 || true
      fi
      echo "fail" > result.txt
    fi
    df -h "${ANDROID_ROOT}" || true
    exit 1
  fi
}

notify_send "A51 ${PACKAGE_NAME} Android 17 build on crave.io started (${BUILD_JOBS} jobs)."

# =============================================================================
# PHASE 1 — kill the stale carrier manifest and re-init Evolution X cnb
# =============================================================================
rm -rf .repo/manifests .repo/manifests.git
repo init \
  -u https://github.com/Evolution-X/manifest \
  -b cnb \
  --git-lfs --depth=1 --no-tags --no-clone-bundle
check_fail

if [[ -n "${EVO_MANIFEST_SHA}" ]]; then
  # Best-effort pin (GitHub serves arbitrary reachable SHAs).
  git -C .repo/manifests fetch --depth=1 origin "${EVO_MANIFEST_SHA}" || \
    git -C .repo/manifests fetch origin "${EVO_MANIFEST_SHA}" || true
  if git -C .repo/manifests cat-file -e "${EVO_MANIFEST_SHA}^{commit}" 2>/dev/null; then
    git -C .repo/manifests checkout --detach "${EVO_MANIFEST_SHA}"
    check_fail
    echo "Pinned Evolution manifest at ${EVO_MANIFEST_SHA}"
  else
    echo "WARNING: pinned SHA ${EVO_MANIFEST_SHA} not fetchable; using cnb tip (292073 behaviour)."
    EVO_MANIFEST_SHA=""
  fi
fi

# =============================================================================
# PHASE 2 — replace stale carrier local manifests with the pinned A51 manifest
# =============================================================================
rm -rf .repo/local_manifests
mkdir -p .repo/local_manifests
curl -fsSL --max-time 60 "${A51_MANIFEST_URL}" -o .repo/local_manifests/a51.xml
check_fail
cp .repo/local_manifests/a51.xml "${ARTIFACT_DIR}/a51-local-manifest.xml"
echo "Installed A51 local manifest from ${A51_MANIFEST_URL}"
ls -la .repo/local_manifests/

# =============================================================================
# PHASE 3 — aggressive local cleanup before the first sync (292073 cleanup_self)
# =============================================================================
rm -rf vendor/lineage-priv
# Stale LOS22-only sepolicy dir that broke job 292171; not part of Evolution cnb.
rm -rf device/qcom/sepolicy_vndr/sm8650


# Obsolete carrier prebuilts. repo refuses to delete a project that has
# uncommitted changes, which aborts "Updating local project lists" and fails
# the entire sync - this is what killed job 292268 after 20 minutes.
rm -rf prebuilts/gcc/linux-x86/arm/arm-linux-androideabi-4.9
rm -rf prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9

# -----------------------------------------------------------------------------
# resync_with_pruning - /opt/crave/resync.sh, but self-healing.
#
# When the workspace was last synced against a different carrier manifest, repo
# has to remove projects the new manifest does not contain. Any of those with a
# dirty working tree makes repo abort the whole sync:
#
#   error: <path>: Cannot remove project: uncommitted changes are present.
#
# resync.sh clears exactly one such project per invocation, so a workspace with
# several of them can never converge in a fixed number of passes. This retries,
# pruning every blocked project reported on each failed attempt.
#
# Only removes projects the incoming manifest does not want, and returns
# immediately if the failure is anything a prune cannot fix - so a genuine sync
# error is never masked.
# -----------------------------------------------------------------------------
resync_with_pruning() {
  local attempt=1 max="${RESYNC_MAX_ATTEMPTS:-8}" out rc
  local -a blocked
  while (( attempt <= max )); do
    echo "--- resync attempt ${attempt}/${max} ---"
    if out="$(/opt/crave/resync.sh 2>&1)"; then
      printf '%s\n' "${out}"
      echo "--- resync succeeded on attempt ${attempt} ---"
      return 0
    fi
    rc=$?
    printf '%s\n' "${out}"
    mapfile -t blocked < <(printf '%s\n' "${out}" \
      | sed -n 's/^error: \(.*\): Cannot remove project.*/\1/p' | sort -u)
    if (( ${#blocked[@]} == 0 )); then
      echo "resync failed (rc=${rc}) for a reason pruning cannot fix." >&2
      return "${rc}"
    fi
    for b in "${blocked[@]}"; do
      if [[ -n "${b}" && -d "${b}" ]]; then
        echo "pruning stale carrier project: ${b}"
        rm -rf "${b}"
      fi
    done
    attempt=$(( attempt + 1 ))
  done
  echo "resync still failing after ${max} attempts." >&2
  return 1
}

# =============================================================================
# PHASE 4 — first Crave resync
# =============================================================================
resync_with_pruning

# =============================================================================
# PHASE 5 — deep clean every managed project (292073 core trick)
# =============================================================================
repo forall -c "git clean -fdx ; git reset --hard HEAD"

# =============================================================================
# PHASE 6 — second Crave resync; this time it MUST fully succeed
# =============================================================================
resync_with_pruning
check_fail

# =============================================================================
# PHASE 7 — verify workspace and record the manifest lockfile
# =============================================================================
if [[ ! -f build/envsetup.sh ]]; then
  echo "REFUSING: workspace is not an Evolution tree after resync." >&2
  echo "fail" > result.txt
  exit 65
fi

MANIFEST_SHA="$(git -C .repo/manifests rev-parse HEAD 2>/dev/null || echo unknown)"
if [[ -n "${EVO_MANIFEST_SHA}" && "${MANIFEST_SHA}" != "${EVO_MANIFEST_SHA}" ]]; then
  # resync.sh may roll the manifest repo forward; re-pin if the object still exists.
  if git -C .repo/manifests cat-file -e "${EVO_MANIFEST_SHA}^{commit}" 2>/dev/null; then
    git -C .repo/manifests checkout --detach "${EVO_MANIFEST_SHA}"
    check_fail
    MANIFEST_SHA="${EVO_MANIFEST_SHA}"
    echo "Re-pinned Evolution manifest at ${EVO_MANIFEST_SHA}"
  else
    echo "WARNING: could not re-pin ${EVO_MANIFEST_SHA}; continuing at cnb tip ${MANIFEST_SHA}"
  fi
fi

repo manifest -r > "${ARTIFACT_DIR}/lockfile.xml"
check_fail
{
  printf 'manifest_sha=%s\n' "${MANIFEST_SHA}"
  printf 'device=%s\n' "${DEVICE}"
  printf 'build_jobs=%s\n' "${BUILD_JOBS}"
  printf 'host_cores=%s\n' "$(nproc --all)"
  printf 'vanilla=%s\n' "true (WITH_GMS=false)"
  date -u '+build_metadata_utc=%Y-%m-%dT%H:%M:%SZ'
} > "${ARTIFACT_DIR}/build-metadata.txt"

notify_send "A51 source sync done ($(printf '%dh:%dm:%ds' $((SECONDS/3600)) $((SECONDS%3600/60)) $((SECONDS%60))))."
df -h "${ANDROID_ROOT}"

# =============================================================================
# PHASE 7b - apply the pinned a51 device tree patches
# =============================================================================
# Placed AFTER both resyncs and the PHASE 5 deep clean on purpose: an earlier
# position would be undone by `repo forall git reset --hard` or by resync.sh
# rolling projects back to their manifest revision.
#
# Idempotent - a persisted workspace that already carries a patch skips it
# rather than failing, so re-running a job is safe.
#
# Patches are documented in patches/device_samsung_a51/README.md. Three of the
# four are defects in the current lineage-23.2 tree, independent of Android 17.
A51_APPLY_PATCHES="${A51_APPLY_PATCHES:-1}"

if [[ "${A51_APPLY_PATCHES}" == "1" ]]; then
  PATCH_BASE_URL="${PUBLIC_REPO_RAW}/${PUBLIC_REVISION}/patches/device_samsung_a51"
  A51_DEVICE_DIR="${ANDROID_ROOT}/device/samsung/a51"
  A51_PATCHES=(
    "0001-a51-releasetools-Write-vbmeta.img-during-OTA-install.patch"
    "0002-a51-Declare-the-super-partition-size-the-hardware-ac.patch"
    "0003-a51-Stop-truncating-the-camera-extra_ids-list.patch"
    "0004-a51-Drop-the-dangling-public-sepolicy-directory.patch"
  )

  if [[ ! -d "${A51_DEVICE_DIR}" ]]; then
    echo "REFUSING: device/samsung/a51 is missing after resync." >&2
    echo "fail" > result.txt
    exit 69
  fi

  PATCH_TMP="$(mktemp -d)"
  patches_applied=0
  patches_skipped=0

  for p in "${A51_PATCHES[@]}"; do
    if ! curl -fsSL --max-time 60 "${PATCH_BASE_URL}/${p}" -o "${PATCH_TMP}/${p}"; then
      echo "REFUSING: could not fetch ${p} from ${PATCH_BASE_URL}" >&2
      echo "fail" > result.txt
      exit 70
    fi
    if git -C "${A51_DEVICE_DIR}" apply --reverse --check "${PATCH_TMP}/${p}" 2>/dev/null; then
      echo "  skip (already applied): ${p}"
      patches_skipped=$((patches_skipped + 1))
    elif git -C "${A51_DEVICE_DIR}" am --3way "${PATCH_TMP}/${p}"; then
      echo "  applied: ${p}"
      patches_applied=$((patches_applied + 1))
    else
      git -C "${A51_DEVICE_DIR}" am --abort 2>/dev/null || true
      echo "REFUSING: failed to apply ${p}" >&2
      echo "fail" > result.txt
      exit 71
    fi
  done

  echo "Device tree patches: ${patches_applied} applied, ${patches_skipped} already present"
  git -C "${A51_DEVICE_DIR}" log --oneline -6
  cp -f "${PATCH_TMP}"/*.patch "${ARTIFACT_DIR}/" 2>/dev/null || true
  {
    printf 'device_tree_patches_applied=%s\n' "${patches_applied}"
    printf 'device_tree_patches_skipped=%s\n' "${patches_skipped}"
    printf 'device_tree_patch_source=%s\n' "${PATCH_BASE_URL}"
  } >> "${ARTIFACT_DIR}/build-metadata.txt"
  rm -rf "${PATCH_TMP}"
  notify_send "A51 device tree patches applied (${patches_applied} new, ${patches_skipped} present)."
else
  echo "Device tree patches SKIPPED (A51_APPLY_PATCHES=0)"
fi


# =============================================================================
# PHASE 8 — product configuration BEFORE lunch, then select the A51 target
# =============================================================================
export WITH_GMS=false
export EVO_BUILD_TYPE=Unofficial
export BUILD_USERNAME=user
export BUILD_HOSTNAME=localhost
export KBUILD_BUILD_USER=user
export KBUILD_BUILD_HOST=localhost

# envsetup.sh and lunch legitimately reference unset shell variables.
set +u
source build/envsetup.sh
check_fail
source build/envsetup.sh
lunch lineage_a51-cp2a-user
check_fail

TARGET_PRODUCT_ACTUAL="${TARGET_PRODUCT:-}"
if [[ "${TARGET_PRODUCT_ACTUAL}" != "lineage_a51" ]]; then
  echo "REFUSING: unexpected target '${TARGET_PRODUCT_ACTUAL}'; expected lineage_a51." >&2
  echo "fail" > result.txt
  exit 68
fi
echo "Lunched ${TARGET_PRODUCT_ACTUAL}-cp2a-${TARGET_BUILD_VARIANT:-user}"

# nounset stays OFF from here on — identical to build 292073.

# =============================================================================
# PHASE 9 — wipe stale outputs, then run the Soong OOM retry ladder (292073)
# =============================================================================
mka installclean
check_fail

CRAVE_SOONG_WORKAROUND="${CRAVE_SOONG_WORKAROUND:-1}"
if [[ "${CRAVE_SOONG_WORKAROUND}" == "1" ]]; then
  do_soong() {
    ( sleep 1800; pkill -9 -e soong_build || true ) &
    local sleep_pid=$!
    notify_send "Soong attempt in progress."
    if m nothing; then
      kill "${sleep_pid}" 2>/dev/null || true
      notify_send "Soong succeeded."
      return 0
    fi
    kill "${sleep_pid}" 2>/dev/null || true
    notify_send "Soong failed."
    return 1
  }

  export GOMEMLIMIT=52GiB GOGC=20 GODEBUG="gctrace=1"
  notify_send "Soong ladder phase 1 (baseline)."
  do_soong || do_soong || do_soong || do_soong
  unset GOMEMLIMIT GOGC GODEBUG
  rm -rf out/soong

  export GOMEMLIMIT=52GiB GOGC=20 GODEBUG="gctrace=1" GOMAXPROCS=12
  notify_send "Soong ladder phase 2 (12 procs)."
  do_soong || do_soong || do_soong || do_soong
  unset GOMEMLIMIT GOGC GODEBUG GOMAXPROCS
  rm -rf out/soong

  export GOMEMLIMIT=52GiB GOGC=20 GODEBUG="gctrace=1" GOMAXPROCS=8
  notify_send "Soong ladder phase 3 (8 procs)."
  do_soong || do_soong || do_soong || do_soong
  unset GOMEMLIMIT GOGC GODEBUG GOMAXPROCS
  rm -rf out/soong

  export GOMEMLIMIT=45GiB GOGC=20 GODEBUG="gctrace=1" GOMAXPROCS=12
  notify_send "Soong ladder phase 4 (45GiB/12 procs)."
  do_soong || do_soong || do_soong || do_soong
  unset GOMEMLIMIT GOGC GODEBUG GOMAXPROCS
  rm -rf out/soong

  export GOMEMLIMIT=52GiB GOGC=20 GODEBUG="gctrace=1" GOMAXPROCS=4
  notify_send "Soong ladder phase 5 (4 procs)."
  do_soong || do_soong || do_soong || do_soong
  unset GOMEMLIMIT GOGC GODEBUG GOMAXPROCS
  rm -rf out/soong

  export GOMEMLIMIT=52GiB GOGC=20 GODEBUG="gctrace=1" GOMAXPROCS=2
  notify_send "Soong ladder phase 6 (2 procs)."
  do_soong || do_soong || do_soong || do_soong
  unset GOMEMLIMIT GOGC GODEBUG GOMAXPROCS
  rm -rf out/soong

  export GOMEMLIMIT=45GiB GOGC=20 GODEBUG="gctrace=1" GOMAXPROCS=6
  notify_send "Soong ladder phase 7 (45GiB/6 procs)."
  do_soong || do_soong || do_soong || do_soong
  unset GOMEMLIMIT GOGC GODEBUG GOMAXPROCS
  rm -rf out/soong

  notify_send "Soong ladder finished."
  unset do_soong
fi

# =============================================================================
# PHASE 10 — the real build (292073 build command, adapted to a51)
# =============================================================================
PRODUCT_OTA_ENFORCE_VINTF_KERNEL_REQUIREMENTS=false m evolution -j"${BUILD_JOBS}"
check_fail

# =============================================================================
# PHASE 11 — success handling and artifact collection
# =============================================================================
echo "success" > result.txt
notify_send "A51 ${PACKAGE_NAME} build on crave.io SUCCEEDED."

shopt -s nullglob
zip_files=( out/target/product/${DEVICE}/${PACKAGE_NAME}*.zip )
if (( ${#zip_files[@]} > 0 )); then
  ls -lh "${zip_files[@]}"
  cp "${zip_files[@]}" "${ARTIFACT_DIR}/"
fi
shopt -u nullglob

BUILD_TIME=$(printf '%dh:%dm:%ds' $((SECONDS/3600)) $((SECONDS%3600/60)) $((SECONDS%60)))
notify_send "A51 build completed. ${BUILD_TIME}."
date -u
df -h "${ANDROID_ROOT}"
echo "ALL DONE"
exit 0
