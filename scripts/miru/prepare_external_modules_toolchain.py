#!/usr/bin/env python3

from pathlib import Path

SCRIPT = Path("scripts/miru/build_external_modules_4.14.190.sh")

text = SCRIPT.read_text()

old_env = '''export PATH="${CLANG_DIR}/bin:${GCC64_DIR}/bin:${GCC32_DIR}/bin:${AOSP_BUILD_TOOLS}/bin:${PATH}"
export ARCH=arm64
export SUBARCH=arm64
export CC=clang
export CLANG_TRIPLE=aarch64-linux-gnu-
export CROSS_COMPILE="${GCC64_DIR}/bin/aarch64-linux-android-"
export CROSS_COMPILE_ARM32="${GCC32_DIR}/bin/arm-linux-androideabi-"
export LD="${GCC64_DIR}/bin/aarch64-linux-android-ld"
export AR="${GCC64_DIR}/bin/aarch64-linux-android-ar"
export NM="${GCC64_DIR}/bin/aarch64-linux-android-nm"
export OBJCOPY="${GCC64_DIR}/bin/aarch64-linux-android-objcopy"
export OBJDUMP="${GCC64_DIR}/bin/aarch64-linux-android-objdump"
export STRIP="${GCC64_DIR}/bin/aarch64-linux-android-strip"
export HOSTCC=gcc
export HOSTCXX=g++
export KBUILD_BUILD_USER=miru
export KBUILD_BUILD_HOST=github-actions
export KBUILD_BUILD_VERSION=1
export KBUILD_BUILD_TIMESTAMP="$(git -C "${KERNEL_DIR}" show -s --format=%cD HEAD)"
export SOURCE_DATE_EPOCH="$(git -C "${KERNEL_DIR}" show -s --format=%ct HEAD)"
export TARGET_BUILD_VARIANT=user

KERNEL_RELEASE="$(make -s -C "${KERNEL_DIR}" O="${OUT_DIR}" kernelrelease)"
'''
new_env = '''export PATH="${CLANG_DIR}/bin:${GCC64_DIR}/bin:${GCC32_DIR}/bin:${AOSP_BUILD_TOOLS}/bin:${PATH}"
export ARCH=arm64
export SUBARCH=arm64
export KBUILD_BUILD_USER=miru
export KBUILD_BUILD_HOST=github-actions
export KBUILD_BUILD_VERSION=1
export KBUILD_BUILD_TIMESTAMP="$(git -C "${KERNEL_DIR}" show -s --format=%cD HEAD)"
export SOURCE_DATE_EPOCH="$(git -C "${KERNEL_DIR}" show -s --format=%ct HEAD)"
export TARGET_BUILD_VARIANT=user

# This downstream kernel invokes scripts/gcc-wrapper.py and selects Clang via
# REAL_CC, not CC.  Reuse the exact make interface from the successful kernel
# build so external modules receive the same compiler, release string and ABI.
MAKE_COMMON=(
  "O=${OUT_DIR}" "ARCH=arm64" "TARGET_PRODUCT=msmnile"
  "BRAND_SHOW_FLAG=oneplus" "TARGET_BUILD_VARIANT=user"
  "CROSS_COMPILE=${GCC64_DIR}/bin/aarch64-linux-android-"
  "CROSS_COMPILE_ARM32=${GCC32_DIR}/bin/arm-linux-androideabi-"
  "REAL_CC=${CLANG_DIR}/bin/clang" "CLANG_TRIPLE=aarch64-linux-gnu-"
  "PYTHON=${AOSP_BUILD_TOOLS}/bin/py2-cmd"
  "HOSTCC=gcc" "HOSTCXX=g++" "LOCALVERSION=+"
)

KERNEL_RELEASE="$(make -s -C "${KERNEL_DIR}" "${MAKE_COMMON[@]}" kernelrelease)"
'''
if text.count(old_env) != 1:
    raise SystemExit("external-module toolchain environment block missing or duplicated")
text = text.replace(old_env, new_env, 1)

# Qualcomm's unpublished AndroidKernelModule.mk added sibling audio source
# directories to every DLKM's include search path.  Isolated per-module builds
# need those same private headers (for example soc/pinctrl-wcd.c ->
# asoc/codecs/core.h) while retaining a single obj-m target.
old_isolated_kbuild = '''text = re.sub(r"^\\s*obj-[^\\n]*$", "", text, flags=re.M)
text += f"\\nobj-m += {target}.o\\n"
'''
new_isolated_kbuild = '''text = re.sub(r"^\\s*obj-[^\\n]*$", "", text, flags=re.M)
text += (
    "\\nEXTRA_CFLAGS += -I$(AUDIO_ROOT)"
    " -I$(AUDIO_ROOT)/soc -I$(AUDIO_ROOT)/ipc"
    " -I$(AUDIO_ROOT)/dsp -I$(AUDIO_ROOT)/dsp/codecs"
    " -I$(AUDIO_ROOT)/asoc -I$(AUDIO_ROOT)/asoc/codecs"
    " -I$(AUDIO_ROOT)/asoc/codecs/wcd934x\\n"
)
text += f"\\nobj-m += {target}.o\\n"
'''
if text.count(old_isolated_kbuild) != 1:
    raise SystemExit("isolated audio Kbuild rewrite block missing or duplicated")
text = text.replace(old_isolated_kbuild, new_isolated_kbuild, 1)

old_audio = '''  make -j4 -C "${KERNEL_DIR}" O="${OUT_DIR}" M="${work}" \\
    AUDIO_ROOT="${AUDIO_ROOT}" \\
'''
new_audio = '''  make -j4 -C "${KERNEL_DIR}" "${MAKE_COMMON[@]}" M="${work}" \\
    AUDIO_ROOT="${AUDIO_ROOT}" \\
'''
if text.count(old_audio) != 1:
    raise SystemExit("audio module make invocation missing or duplicated")
text = text.replace(old_audio, new_audio, 1)

old_extend = '''  make -j4 -C "${KERNEL_DIR}" O="${OUT_DIR}" M="${work}" \\
    MODNAME=audio_extend_dlkm BOARD_PLATFORM=msmnile \\
'''
new_extend = '''  make -j4 -C "${KERNEL_DIR}" "${MAKE_COMMON[@]}" M="${work}" \\
    MODNAME=audio_extend_dlkm BOARD_PLATFORM=msmnile \\
'''
if text.count(old_extend) != 1:
    raise SystemExit("OPlus audio extension make invocation missing or duplicated")
text = text.replace(old_extend, new_extend, 1)

old_sleepmon = '''make -j4 -C "${KERNEL_DIR}" O="${OUT_DIR}" M="${sleepmon_work}" \\
  CC="${CLANG_DIR}/bin/clang" \\
'''
new_sleepmon = '''make -j4 -C "${KERNEL_DIR}" "${MAKE_COMMON[@]}" M="${sleepmon_work}" \\
'''
if text.count(old_sleepmon) != 1:
    raise SystemExit("OPlus subsystem sleep-monitor make invocation missing or duplicated")
text = text.replace(old_sleepmon, new_sleepmon, 1)

old_wlan = '''make -j4 -C "${KERNEL_DIR}" O="${OUT_DIR}" M="${WLAN_ROOT}" \\
  WLAN_ROOT="${WLAN_ROOT}" \\
'''
new_wlan = '''make -j4 -C "${KERNEL_DIR}" "${MAKE_COMMON[@]}" M="${WLAN_ROOT}" \\
  WLAN_ROOT="${WLAN_ROOT}" \\
'''
if text.count(old_wlan) != 1:
    raise SystemExit("WLAN module make invocation missing or duplicated")
text = text.replace(old_wlan, new_wlan, 1)

SCRIPT.write_text(text)
print("External-module builder now uses the kernel toolchain and complete audio include topology.")
