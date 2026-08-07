#!/usr/bin/env bash
set -Eeuo pipefail

# Public source:
# https://github.com/dandysuper/a51-evox-a17-port-plan
#
# Run only through a normal Crave build job after a moderator approves an
# Android 17 carrier project. Do not run this from a devspace or crave ssh.

if [[ "${DCDEVSPACE:-0}" == "1" || "$(pwd -P)" == /crave-devspaces* ]]; then
  echo "REFUSING: use a normal crave run build job, not a devspace." >&2
  exit 64
fi

readonly ANDROID_ROOT="/tmp/src/android"
readonly EVO_MANIFEST_SHA="05755535e93f9e83ebccbda790ccc94102d5abec"
readonly PUBLIC_REPO_RAW="https://raw.githubusercontent.com/dandysuper/a51-evox-a17-port-plan"
readonly PUBLIC_REVISION="${A51_PUBLIC_REVISION:-main}"
readonly A51_MANIFEST_URL="${PUBLIC_REPO_RAW}/${PUBLIC_REVISION}/local_manifests/a51.xml"
readonly BUILD_JOBS="${BUILD_JOBS:-16}"

if [[ ! -d "${ANDROID_ROOT}" ]]; then
  echo "REFUSING: expected Crave Android workspace ${ANDROID_ROOT} is missing." >&2
  exit 65
fi

if [[ ! -x /opt/crave/resync.sh ]]; then
  echo "REFUSING: /opt/crave/resync.sh is unavailable." >&2
  exit 66
fi

cd "${ANDROID_ROOT}"
exec > >(tee -a /tmp/a51-evox-crave-build.log) 2>&1

trap 'status=$?; echo "FAILED at line ${LINENO} (exit ${status})"; df -h "${ANDROID_ROOT}" || true; exit "${status}"' ERR

echo "Starting public A51 Evolution X Android 17 source setup/build"
echo "Script source: ${PUBLIC_REPO_RAW}/${PUBLIC_REVISION}/crave-sync-build.sh"
date -u
uname -a
nproc --all
free -h
df -h "${ANDROID_ROOT}"

# Preserve the carrier's local manifests without recursively deleting them.
if [[ -e .repo/local_manifests ]]; then
  backup=".repo/local_manifests.pre-evox.$(date -u +%Y%m%dT%H%M%SZ)"
  mv -- .repo/local_manifests "${backup}"
  echo "Preserved previous local manifests at ${backup}"
fi

repo init \
  -u https://github.com/Evolution-X/manifest \
  -b cnb \
  --git-lfs \
  --depth 1

# Freeze the manifest revision documented by the port plan even if cnb moves.
git -C .repo/manifests fetch --depth 1 origin "${EVO_MANIFEST_SHA}"
git -C .repo/manifests checkout --detach FETCH_HEAD

mkdir -p .repo/local_manifests
curl -fsSL "${A51_MANIFEST_URL}" \
  -o .repo/local_manifests/a51.xml.download
mv -- .repo/local_manifests/a51.xml.download .repo/local_manifests/a51.xml

# Crave's documented unsupported-ROM sync helper. The script itself performs
# no manual recursive deletion.
/opt/crave/resync.sh

repo manifest -r > /tmp/a51-evolution-cnb-lock.xml
df -h "${ANDROID_ROOT}"

export WITH_GMS=false
export EVO_BUILD_TYPE=Unofficial
. build/envsetup.sh
lunch lineage_a51-cp2a-user
m evolution -j"${BUILD_JOBS}"

echo "Build command completed"
date -u
df -h "${ANDROID_ROOT}"
