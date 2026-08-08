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
#   4. run /opt/crave/resync.sh twice — the second pass must fully succeed;
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

# =============================================================================
# PHASE 4 — first Crave resync
# =============================================================================
/opt/crave/resync.sh

# =============================================================================
# PHASE 5 — deep clean every managed project (292073 core trick)
# =============================================================================
repo forall -c "git clean -fdx ; git reset --hard HEAD"

# =============================================================================
# PHASE 6 — second Crave resync; this time it MUST fully succeed
# =============================================================================
/opt/crave/resync.sh
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
