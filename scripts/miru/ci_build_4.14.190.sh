#!/usr/bin/env bash
set -Eeuo pipefail

BASE_SHA=59858c8f798778f4e6c1c4449baba631e353600e
SCAFFOLD_SHA=5d8cba39fefb935c6feaf30ea1a57dfffa80273a
STABLE_SHA=d2d05bcf4b4edf8d028fa420dee3c6644aa5b4ac
VENDOR_SHA=a21f9352e70a8685556582465309f8eb3fe401cb

ANDROID_ROOT="${RUNNER_TEMP}/android-root"
KERNEL_WORKTREE="${ANDROID_ROOT}/kernel/msm-4.14"
VENDOR_SOURCE="${RUNNER_TEMP}/oneplus-sm8150-vendor-source"
OUT_DIR="${ANDROID_ROOT}/out/h40-kernel"
DTS_OUT_DIR="${ANDROID_ROOT}/out/h40-production-dts"
ARTIFACT_DIR="${ANDROID_ROOT}/out/h40-artifacts"
BUILD_LOG="${ANDROID_ROOT}/out/h40-build.log"
TOOLCHAIN_ROOT="${RUNNER_TEMP}/miru-toolchains"
DIAG_DIR="${GITHUB_WORKSPACE}/build-diagnostics"

mkdir -p "${DIAG_DIR}"
exec > >(tee -a "${DIAG_DIR}/ci-console.log") 2>&1
trap 'status=$?; echo "${status}" > "${DIAG_DIR}/ci-exit-code.txt"; exit "${status}"' EXIT

echo "== Miru H.40 Android 4.14.190 CI build =="
echo "head=$(git rev-parse HEAD)"

# Fetch only the distant commits required by the source-level sanity checks.
git fetch --no-tags --depth=1 origin "${BASE_SHA}"
git fetch --no-tags --depth=1 origin "${SCAFFOLD_SHA}"
git fetch --no-tags --depth=1 origin "${STABLE_SHA}"

# Sanity gate: no unresolved index state, no conflict headers, clean patch,
# authentic two-parent merge scaffold, complete ledger, and expected version.
git diff --check "${BASE_SHA}" HEAD > "${DIAG_DIR}/diff-check.txt" 2>&1
if git grep -nE '^(<<<<<<< .+|>>>>>>> .+)$' -- . \
    ':!Documentation/miru/lts-4.14.190-conflicts.md' \
    > "${DIAG_DIR}/conflict-markers.txt"; then
  echo "Unexpected Git conflict headers found"
  cat "${DIAG_DIR}/conflict-markers.txt"
  exit 1
else
  : > "${DIAG_DIR}/conflict-markers.txt"
fi

test -z "$(git ls-files -u)"
test "$(sed -n 's/^SUBLEVEL = //p' Makefile | head -n1)" = "190"
grep -Fq -- '- Resolved conflicts: 28' Documentation/miru/lts-4.14.190-conflicts.md
grep -Fq -- '- Remaining conflicts: 0' Documentation/miru/lts-4.14.190-conflicts.md

git cat-file -p "${SCAFFOLD_SHA}" > "${DIAG_DIR}/merge-scaffold.txt"
test "$(grep -c '^parent ' "${DIAG_DIR}/merge-scaffold.txt")" = "2"
grep -Fq "parent ${STABLE_SHA}" "${DIAG_DIR}/merge-scaffold.txt"

{
  echo "Sanity gate: PASS"
  echo "head=$(git rev-parse HEAD)"
  echo "kernel_version=4.14.190"
  echo "conflicts=28/28 resolved"
  echo "unmerged_index_entries=0"
} | tee "${DIAG_DIR}/sanity-summary.txt"

# GitHub's Ubuntu image contains most dependencies already; install the
# remaining deterministic kernel-build prerequisites explicitly.
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  build-essential bison flex libssl-dev libelf-dev cpio kmod rsync \
  zlib1g-dev libncurses-dev xz-utils file

# Recreate the Android source layout used by the official OnePlus tree:
#   android/kernel/msm-4.14  (this integration branch)
#   android/vendor/...       (official modules/vendor repository)
# Building from the GitHub checkout path directly breaks the relative OPlus
# symlinks even when the vendor repository is present elsewhere.
rm -rf "${ANDROID_ROOT}" "${VENDOR_SOURCE}"
mkdir -p "${ANDROID_ROOT}/kernel" "${ANDROID_ROOT}/out"
git worktree add --detach "${KERNEL_WORKTREE}" HEAD

git init -q "${VENDOR_SOURCE}"
git -C "${VENDOR_SOURCE}" remote add origin \
  https://github.com/KAI-Miru/android_kernel_modules_and_devicetree_oneplus_sm8150.git
git -C "${VENDOR_SOURCE}" fetch -q --depth=1 --filter=blob:none origin "${VENDOR_SHA}"
git -C "${VENDOR_SOURCE}" checkout -q --detach FETCH_HEAD
test "$(git -C "${VENDOR_SOURCE}" rev-parse HEAD)" = "${VENDOR_SHA}"
test -d "${VENDOR_SOURCE}/vendor"
mkdir -p "${ANDROID_ROOT}/vendor"
rsync -a "${VENDOR_SOURCE}/vendor/" "${ANDROID_ROOT}/vendor/"

# Record the actual checked-in symlink graph and prove that the active Kconfig
# dependency that blocked the first CI attempt now resolves through vendor/oplus.
{
  echo "kernel_worktree=${KERNEL_WORKTREE}"
  echo "kernel_head=$(git -C "${KERNEL_WORKTREE}" rev-parse HEAD)"
  echo "vendor_source_commit=$(git -C "${VENDOR_SOURCE}" rev-parse HEAD)"
  echo "main_symlink_count=$(find "${KERNEL_WORKTREE}" -type l | wc -l)"
  echo "vendor_symlink_count=$(find "${ANDROID_ROOT}/vendor" -type l | wc -l)"
  echo
  echo "block/oplus_foreground_io_opt -> $(readlink "${KERNEL_WORKTREE}/block/oplus_foreground_io_opt")"
  echo
  find "${KERNEL_WORKTREE}" -type l -printf '%P -> %l\n' | sort
} > "${DIAG_DIR}/workspace-layout.txt"

test -L "${KERNEL_WORKTREE}/block/oplus_foreground_io_opt"
test -f "${KERNEL_WORKTREE}/block/oplus_foreground_io_opt/Kconfig"
test -f "${KERNEL_WORKTREE}/drivers/android/oplus_binder_stats.c"
test -d "${ANDROID_ROOT}/vendor/oplus"
test -f "${ANDROID_ROOT}/vendor/oplus/kernel/power/midas/binder_stats_dev.c"
test -d "${ANDROID_ROOT}/vendor/qcom/opensource/audio-kernel"
test -d "${ANDROID_ROOT}/vendor/qcom/opensource/wlan"

rm -rf "${TOOLCHAIN_ROOT}"
mkdir -p "${TOOLCHAIN_ROOT}"

fetch_root() {
  local url="$1" commit="$2" dest="$3"
  git init -q "${dest}"
  git -C "${dest}" remote add origin "${url}"
  git -C "${dest}" fetch -q --depth=1 --filter=blob:none origin "${commit}"
  git -C "${dest}" checkout -q --detach FETCH_HEAD
}

fetch_sparse() {
  local url="$1" commit="$2" dest="$3" sparse_path="$4"
  git init -q "${dest}"
  git -C "${dest}" remote add origin "${url}"
  git -C "${dest}" sparse-checkout init --cone
  git -C "${dest}" sparse-checkout set "${sparse_path}"
  git -C "${dest}" fetch -q --depth=1 --filter=blob:none origin "${commit}"
  git -C "${dest}" checkout -q --detach FETCH_HEAD
}

fetch_sparse \
  https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86 \
  252aba16f513a857bc923172f67b0e55e23de35f \
  "${TOOLCHAIN_ROOT}/clang-repo" clang-r377782c

fetch_root \
  https://android.googlesource.com/platform/prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9 \
  606f80986096476912e04e5c2913685a8f2c3b65 \
  "${TOOLCHAIN_ROOT}/gcc64"

fetch_root \
  https://android.googlesource.com/platform/prebuilts/gcc/linux-x86/arm/arm-linux-androideabi-4.9 \
  b0c6a654327ca8796bed1e61dffcf523d04dceaa \
  "${TOOLCHAIN_ROOT}/gcc32"

fetch_sparse \
  https://android.googlesource.com/platform/prebuilts/build-tools \
  7322db1e1e4715fe217a27f721613e6be8438676 \
  "${TOOLCHAIN_ROOT}/build-tools" linux-x86

CLANG_DIR="${TOOLCHAIN_ROOT}/clang-repo/clang-r377782c"
GCC64_DIR="${TOOLCHAIN_ROOT}/gcc64"
GCC32_DIR="${TOOLCHAIN_ROOT}/gcc32"
AOSP_BUILD_TOOLS="${TOOLCHAIN_ROOT}/build-tools/linux-x86"

printf '%s  %s\n' \
  6618ecab73b79a70b79263d2f477f669e564d81ca802112d2e5f93c74c6b22ca \
  "${CLANG_DIR}/bin/clang" | sha256sum -c -
printf '%s  %s\n' \
  2a663de4ce3d702fe3f2a0de48cac366be676f850c2f5732d9cc2e4acb9335e2 \
  "${GCC64_DIR}/bin/aarch64-linux-android-ld" | sha256sum -c -
printf '%s  %s\n' \
  9565b7fc362bdf87032d44eea1087f25dcdd3a6655b39caa6f934640791f15d8 \
  "${GCC64_DIR}/bin/aarch64-linux-android-as" | sha256sum -c -
printf '%s  %s\n' \
  2f78058a8549bc5c099dbea16d9f3dc571e072b1ade906c3539e419787b502dd \
  "${GCC32_DIR}/bin/arm-linux-androideabi-as" | sha256sum -c -
printf '%s  %s\n' \
  5630a485d7c597d137fa462626213007e8865cf549677e1f727d131695ec830c \
  "${AOSP_BUILD_TOOLS}/bin/py2-cmd" | sha256sum -c -
printf '%s  %s\n' \
  e42381e7111b3e9336895284a95b0a404479a45cfcd787e6431021d277ccbe44 \
  "${AOSP_BUILD_TOOLS}/bin/gavinhoward-bc" | sha256sum -c -
printf '%s  %s\n' \
  c337f911c36e317e1fbbd9c3baa1cdb8457f591051f8f871eaa4964136f0dec5 \
  "${AOSP_BUILD_TOOLS}/bin/toybox" | sha256sum -c -

{
  echo "clang_commit=252aba16f513a857bc923172f67b0e55e23de35f"
  echo "clang_path=clang-r377782c"
  "${CLANG_DIR}/bin/clang" --version | head -n1
  echo "gcc64_commit=606f80986096476912e04e5c2913685a8f2c3b65"
  "${GCC64_DIR}/bin/aarch64-linux-android-ld" --version | head -n1
  echo "gcc32_commit=b0c6a654327ca8796bed1e61dffcf523d04dceaa"
  "${GCC32_DIR}/bin/arm-linux-androideabi-as" --version | head -n1
  echo "build_tools_commit=7322db1e1e4715fe217a27f721613e6be8438676"
  "${AOSP_BUILD_TOOLS}/bin/py2-cmd" --version 2>&1 | head -n1 || true
} | tee "${DIAG_DIR}/toolchain-manifest.txt"

export ANDROID_ROOT OUT_DIR DTS_OUT_DIR ARTIFACT_DIR BUILD_LOG
export CLANG_DIR GCC64_DIR GCC32_DIR AOSP_BUILD_TOOLS
export KERNEL_DIR="${KERNEL_WORKTREE}"
export CONFIG_MODE=stock
export KERNEL_LOCALVERSION=-miru-h40-lts190-ci1
export MODULE_SIG_POLICY=permit-untrusted
export SKIP_PRODUCTION_DTS=1
export JOBS=4
export KBUILD_BUILD_USER=miru
export KBUILD_BUILD_HOST=github-actions
export KBUILD_BUILD_VERSION=1
export KBUILD_BUILD_TIMESTAMP="$(git -C "${KERNEL_WORKTREE}" show -s --format=%cD HEAD)"
export SOURCE_DATE_EPOCH="$(git -C "${KERNEL_WORKTREE}" show -s --format=%ct HEAD)"

"${KERNEL_WORKTREE}/h40-repro/build-h40.sh" --clean 2>&1 | tee "${DIAG_DIR}/build-console.log"

for rel in \
  arch/arm64/boot/Image \
  arch/arm64/boot/Image.gz \
  arch/arm64/boot/Image.gz-dtb \
  vmlinux System.map Module.symvers .config; do
  test -s "${OUT_DIR}/${rel}"
done

test -s "${ARTIFACT_DIR}/arch/arm64/boot/Image"
test -s "${ARTIFACT_DIR}/Module.symvers"
grep -Fq 'CONFIG_LOCALVERSION="-miru-h40-lts190-ci1"' "${OUT_DIR}/.config"
grep -Fq '# CONFIG_MODULE_SIG_FORCE is not set' "${OUT_DIR}/.config"
grep -Fq 'CONFIG_MODVERSIONS=y' "${OUT_DIR}/.config"

banner="$(strings "${OUT_DIR}/arch/arm64/boot/Image" | grep -m1 '^Linux version 4\.14\.190-' || true)"
test -n "${banner}"

cp "${BUILD_LOG}" "${DIAG_DIR}/h40-build.log"
"${KERNEL_WORKTREE}/scripts/diffconfig" \
  "${KERNEL_WORKTREE}/h40-repro/config/GM1911_11_H.40.config" "${OUT_DIR}/.config" \
  > "${DIAG_DIR}/config-diff.txt" || true

{
  echo "result=SUCCESS"
  echo "head=$(git -C "${KERNEL_WORKTREE}" rev-parse HEAD)"
  echo "vendor_source_commit=${VENDOR_SHA}"
  echo "banner=${banner}"
  echo "image_size=$(stat -c %s "${OUT_DIR}/arch/arm64/boot/Image")"
  echo "image_gz_size=$(stat -c %s "${OUT_DIR}/arch/arm64/boot/Image.gz")"
  echo "image_gz_dtb_size=$(stat -c %s "${OUT_DIR}/arch/arm64/boot/Image.gz-dtb")"
  echo "dtb_count=$(find "${OUT_DIR}/arch/arm64/boot/dts" -type f -name '*.dtb' | wc -l)"
  echo "dtbo_count=$(find "${OUT_DIR}/arch/arm64/boot/dts" -type f -name '*.dtbo' | wc -l)"
  echo "ko_count=$(find "${OUT_DIR}" -type f -name '*.ko' | wc -l)"
  sha256sum \
    "${OUT_DIR}/arch/arm64/boot/Image" \
    "${OUT_DIR}/arch/arm64/boot/Image.gz" \
    "${OUT_DIR}/arch/arm64/boot/Image.gz-dtb" \
    "${OUT_DIR}/.config" \
    "${OUT_DIR}/System.map" \
    "${OUT_DIR}/Module.symvers"
} | tee "${DIAG_DIR}/build-summary.txt"

cp "${DIAG_DIR}/build-summary.txt" "${ARTIFACT_DIR}/BUILD-SUMMARY.txt"
cp "${DIAG_DIR}/toolchain-manifest.txt" "${ARTIFACT_DIR}/TOOLCHAIN-MANIFEST.txt"
cp "${DIAG_DIR}/sanity-summary.txt" "${ARTIFACT_DIR}/SANITY-SUMMARY.txt"
cp "${DIAG_DIR}/workspace-layout.txt" "${ARTIFACT_DIR}/WORKSPACE-LAYOUT.txt"
cp "${DIAG_DIR}/config-diff.txt" "${ARTIFACT_DIR}/CONFIG-DIFF.txt"
cp "${DIAG_DIR}/h40-build.log" "${ARTIFACT_DIR}/h40-build.log"

echo "Clean kernel build and output validation: PASS"
