#!/usr/bin/env bash
# =============================================================================
#  Samsung Galaxy A51 (a51 / SM-A515F / Exynos 9611)
#  Evolution X 12.1 "cnb" = Android 17
#
#  Public source: https://github.com/dandysuper/a51-evox-a17-port-plan
#
#  One-shot, fully automatic. Syncs, applies the device tree patches, builds.
#  Safe to re-run: patch application is idempotent.
#
#  Usage (from your machine, detached):
#      tmux new -s a51
#      crave run --no-patch -- "curl -fsSL <raw-url-of-this-file> | bash"
#      Ctrl-B then D
#
#  Run only as a normal crave run build job. Never in a devspace or crave ssh.
# =============================================================================
set -Eeo pipefail          # NOTE: deliberately NOT -u; see envsetup section

# ---------------------------------------------------------------- guards ----
if [[ "${DCDEVSPACE:-0}" == "1" || "$(pwd -P)" == /crave-devspaces* ]]; then
  echo "REFUSING: use a normal crave run build job, not a devspace." >&2
  exit 64
fi

readonly ANDROID_ROOT="/tmp/src/android"
readonly EVO_MANIFEST_SHA="05755535e93f9e83ebccbda790ccc94102d5abec"
readonly PUBLIC_REPO_RAW="https://raw.githubusercontent.com/dandysuper/a51-evox-a17-port-plan"
readonly PUBLIC_REVISION="${A51_PUBLIC_REVISION:-main}"
readonly BASE_URL="${PUBLIC_REPO_RAW}/${PUBLIC_REVISION}"
readonly A51_MANIFEST_URL="${BASE_URL}/local_manifests/a51.xml"
readonly PATCH_BASE_URL="${BASE_URL}/patches/device_samsung_a51"
readonly LUNCH_TARGET="lineage_a51-cp2a-user"
# FIX 4: was hardcoded 16. Workers report ~10 cores; oversubscribing with
# RAM already tight invites OOM in metalava/soong.
readonly BUILD_JOBS="${BUILD_JOBS:-$(nproc --all)}"

readonly PATCHES=(
  "0001-a51-releasetools-Write-vbmeta.img-during-OTA-install.patch"
  "0002-a51-Declare-the-super-partition-size-the-hardware-ac.patch"
  "0003-a51-Stop-truncating-the-camera-extra_ids-list.patch"
  "0004-a51-Drop-the-dangling-public-sepolicy-directory.patch"
)

[[ -d "${ANDROID_ROOT}" ]] || { echo "REFUSING: ${ANDROID_ROOT} missing." >&2; exit 65; }
[[ -x /opt/crave/resync.sh ]] || { echo "REFUSING: /opt/crave/resync.sh unavailable." >&2; exit 66; }

cd "${ANDROID_ROOT}"

# FIX 5: log and lockfile live in the workspace, not /tmp. /tmp on a worker is
# small and ephemeral - Crave cannot collect artifacts from it.
readonly ARTIFACT_DIR="${ANDROID_ROOT}/a51-build-artifacts"
mkdir -p "${ARTIFACT_DIR}"
exec > >(tee -a "${ARTIFACT_DIR}/build.log") 2>&1

trap 'st=$?; echo; echo "FAILED at line ${LINENO} (exit ${st})"; df -h "${ANDROID_ROOT}" || true; exit "${st}"' ERR

step() { echo; echo "=================================================="; echo ">>> $*"; echo "=================================================="; }

step "Environment"
echo "script rev : ${PUBLIC_REVISION}"
echo "target     : ${LUNCH_TARGET}"
echo "jobs       : ${BUILD_JOBS}"
date -u; uname -m; nproc --all; free -h; df -h "${ANDROID_ROOT}"

# ------------------------------------------------------------- preflight ----
# FIX 2: repo init uses --depth 1 per Crave's rules, but the local manifest
# pins 40-char SHAs. Shallow fetch of an arbitrary SHA only reliably works
# while that SHA is still the branch tip. Rather than silently break the day
# upstream moves, check it and say so.
step "Preflight: are the pinned revisions still branch tips?"
check_tip() {
  local repo="$1" branch="$2" pinned="$3" head
  head="$(curl -sSf "https://api.github.com/repos/${repo}/commits/${branch}" \
          | sed -n 's/.*"sha": *"\([0-9a-f]\{40\}\)".*/\1/p' | head -1)" || return 0
  if [[ -z "${head}" ]]; then
    echo "  ?  ${repo}@${branch} - could not query (rate limit?), skipping"
  elif [[ "${head}" == "${pinned}" ]]; then
    echo "  OK ${repo}@${branch}"
  else
    echo "  !! ${repo}@${branch} MOVED"
    echo "       pinned ${pinned}"
    echo "       tip    ${head}"
    echo "       Shallow fetch of a non-tip SHA may fail. If sync errors here,"
    echo "       re-run with A51_NO_SHALLOW=1 to disable --depth 1."
  fi
}
check_tip Parbindar7/android_device_samsung_a51                  lineage-23.2 b9b86945f85114ed28076602c49b83051337ff85
check_tip Parbindar7/android_device_samsung_universal9611-common lineage-24.0 f2dffabd0c7600f5717dc42548b75f33a57d4626
check_tip Parbindar7/android_kernel_samsung_universal9611        lineage-24.0 9c4dcd26bf44c78e96885c66ba267f15b729e082

# ------------------------------------------------------------- repo init ----
step "repo init"
if [[ -e .repo/local_manifests ]]; then
  backup=".repo/local_manifests.pre-evox.$(date -u +%Y%m%dT%H%M%SZ)"
  mv -- .repo/local_manifests "${backup}"
  echo "preserved previous local manifests at ${backup}"
fi

depth_args=(--depth 1)
[[ "${A51_NO_SHALLOW:-0}" == "1" ]] && depth_args=() && echo "shallow clone DISABLED by A51_NO_SHALLOW"

repo init -u https://github.com/Evolution-X/manifest -b cnb --git-lfs "${depth_args[@]}"

git -C .repo/manifests fetch --depth 1 origin "${EVO_MANIFEST_SHA}"
git -C .repo/manifests checkout --detach FETCH_HEAD
echo "manifest pinned to ${EVO_MANIFEST_SHA}"

step "Local manifest"
mkdir -p .repo/local_manifests
curl -fsSL "${A51_MANIFEST_URL}" -o .repo/local_manifests/a51.xml.dl
mv -- .repo/local_manifests/a51.xml.dl .repo/local_manifests/a51.xml
grep -c '<project' .repo/local_manifests/a51.xml | xargs echo "projects declared:"

# ------------------------------------------------------------------ sync ----
step "Sync (Crave resync.sh)"
/opt/crave/resync.sh

# FIX 3: resync.sh may re-init or reset .repo/manifests, silently discarding
# the pin above. That would be an invisible reproducibility failure.
step "Verify the manifest pin survived resync"
actual="$(git -C .repo/manifests rev-parse HEAD)"
if [[ "${actual}" == "${EVO_MANIFEST_SHA}" ]]; then
  echo "OK  manifest still at ${EVO_MANIFEST_SHA}"
else
  echo "!!  resync.sh MOVED the manifest pin"
  echo "      expected ${EVO_MANIFEST_SHA}"
  echo "      actual   ${actual}"
  echo "    Build continues, but this build is NOT reproducible from the"
  echo "    documented manifest revision. Record this in the build notes."
fi

# --------------------------------------------------------------- patches ----
# Idempotent: a Crave workspace persists between jobs, so a re-run must not
# fail on already-applied patches.
step "Applying device tree patches"
pdir="${ANDROID_ROOT}/device/samsung/a51"
[[ -d "${pdir}" ]] || { echo "device/samsung/a51 missing after sync" >&2; exit 67; }
tmp_patches="$(mktemp -d)"
applied=0; skipped=0
for p in "${PATCHES[@]}"; do
  curl -fsSL "${PATCH_BASE_URL}/${p}" -o "${tmp_patches}/${p}"
  if git -C "${pdir}" apply --reverse --check "${tmp_patches}/${p}" 2>/dev/null; then
    echo "  skip (already applied): ${p}"; skipped=$((skipped+1))
  elif git -C "${pdir}" am --3way "${tmp_patches}/${p}"; then
    echo "  applied: ${p}"; applied=$((applied+1))
  else
    git -C "${pdir}" am --abort 2>/dev/null || true
    echo "FAILED to apply ${p}" >&2; exit 68
  fi
done
echo "patches: ${applied} applied, ${skipped} already present"
git -C "${pdir}" log --oneline -6

# -------------------------------------------------------------- lockfile ----
step "Revision lockfile"
repo manifest -r -o "${ARTIFACT_DIR}/lockfile.xml" \
  && echo "lockfile.xml: $(wc -l < "${ARTIFACT_DIR}/lockfile.xml") lines" \
  || echo "WARN: lockfile generation failed (shallow clone?)"

# ----------------------------------------------------------------- build ----
step "envsetup + lunch"
export WITH_GMS=false          # no default exists upstream; must be explicit
export EVO_BUILD_TYPE=Unofficial

# FIX 1: build/envsetup.sh references unset variables throughout and aborts
# under nounset. This was the guaranteed failure in the previous revision.
set +u
# shellcheck disable=SC1091
source build/envsetup.sh
lunch "${LUNCH_TARGET}"
set -u

[[ -n "${TARGET_PRODUCT:-}" ]] || { echo "lunch did not set TARGET_PRODUCT" >&2; exit 69; }
[[ "${TARGET_PRODUCT}" == "lineage_a51" ]] || { echo "WRONG TARGET: ${TARGET_PRODUCT}" >&2; exit 70; }
echo "TARGET_PRODUCT=${TARGET_PRODUCT}  WITH_GMS=${WITH_GMS}  EVO_BUILD_TYPE=${EVO_BUILD_TYPE}"

step "Build"
m evolution -j"${BUILD_JOBS}"

# ------------------------------------------------------------- artifacts ----
step "Artifacts"
OUT="out/target/product/a51"
ls -lh "${OUT}"/*.zip 2>/dev/null || echo "no zip in ${OUT}"
for i in boot recovery dtbo vbmeta super; do
  [[ -f "${OUT}/${i}.img" ]] && printf "  %-9s %14s bytes\n" "${i}" "$(stat -c%s "${OUT}/${i}.img")"
done
cp -f "${OUT}"/*.zip "${ARTIFACT_DIR}/" 2>/dev/null || true

step "Partition audit"
echo "Physical super on SM-A515F is 6382682112 bytes."
echo "Patch 0002 overrides the common tree's 6836715520 declaration."
echo "boot <= 61865984 | recovery <= 71106560 | dtbo <= 8388608"

step "DONE"
date -u; df -h "${ANDROID_ROOT}"
