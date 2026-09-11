#!/usr/bin/env bash
set -Eeuo pipefail

ANDROID_ROOT="${RUNNER_TEMP}/android-root"
KERNEL_DIR="${ANDROID_ROOT}/kernel/msm-4.14"
VENDOR_ROOT="${ANDROID_ROOT}/vendor"
OUT_DIR="${ANDROID_ROOT}/out/h40-kernel"
TOOLCHAIN_ROOT="${RUNNER_TEMP}/miru-toolchains"
CLANG_DIR="${TOOLCHAIN_ROOT}/clang-repo/clang-r377782c"
GCC64_DIR="${TOOLCHAIN_ROOT}/gcc64"
GCC32_DIR="${TOOLCHAIN_ROOT}/gcc32"
AOSP_BUILD_TOOLS="${TOOLCHAIN_ROOT}/build-tools/linux-x86"
MODULE_WORK="${RUNNER_TEMP}/miru-external-modules"
PACKAGE_DIR="${MODULE_WORK}/dropin"
REPORT_DIR="${GITHUB_WORKSPACE}/external-module-diagnostics"
AUDIO_ROOT="${VENDOR_ROOT}/qcom/opensource/audio-kernel"
WLAN_PARENT="${VENDOR_ROOT}/qcom/opensource/wlan"
AUDIO_ANDROID_OUT="${MODULE_WORK}/android-out"
CUMULATIVE_SYMVERS="${MODULE_WORK}/all-external.symvers"

mkdir -p "${MODULE_WORK}" "${PACKAGE_DIR}" "${REPORT_DIR}" "${AUDIO_ANDROID_OUT}"
: > "${CUMULATIVE_SYMVERS}"
exec > >(tee -a "${REPORT_DIR}/external-modules-console.log") 2>&1
trap 'status=$?; echo "${status}" > "${REPORT_DIR}/external-modules-exit-code.txt"; exit "${status}"' EXIT

for path in \
  "${KERNEL_DIR}" "${VENDOR_ROOT}" "${OUT_DIR}/Module.symvers" \
  "${OUT_DIR}/include/generated/utsrelease.h" "${CLANG_DIR}/bin/clang"; do
  test -e "${path}"
done

export PATH="${CLANG_DIR}/bin:${GCC64_DIR}/bin:${GCC32_DIR}/bin:${AOSP_BUILD_TOOLS}/bin:${PATH}"
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
EXPECTED_VERMAGIC="${KERNEL_RELEASE} SMP preempt mod_unload modversions aarch64"
echo "kernel_release=${KERNEL_RELEASE}" | tee "${REPORT_DIR}/kernel-release.txt"
echo "expected_vermagic=${EXPECTED_VERMAGIC}" | tee -a "${REPORT_DIR}/kernel-release.txt"
test "${KERNEL_RELEASE}" = "4.14.190-miru-h40-lts190-ci1+"

# Copy the six matching modules already produced by the successful core build.
declare -A IN_TREE_MODULES=(
  [mpq-adapter.ko]="drivers/media/platform/msm/dvb/adapter/mpq-adapter.ko"
  [mpq-dmx-hw-plugin.ko]="drivers/media/platform/msm/dvb/demux/mpq-dmx-hw-plugin.ko"
  [msm_11ad_proxy.ko]="drivers/platform/msm/msm_11ad/msm_11ad_proxy.ko"
  [rdbg.ko]="drivers/char/rdbg.ko"
  [tspp.ko]="drivers/media/platform/msm/broadcast/tspp.ko"
  [wil6210.ko]="drivers/net/wireless/ath/wil6210/wil6210.ko"
)
for public in "${!IN_TREE_MODULES[@]}"; do
  source_path="${OUT_DIR}/${IN_TREE_MODULES[${public}]}"
  test -s "${source_path}"
  cp -f "${source_path}" "${PACKAGE_DIR}/${public}"
done

# External audio module builder.  The proprietary AndroidKernelModule.mk helper
# built each LOCAL_MODULE in a separate object directory.  Recreate that model:
# copy the source group, retain only the requested obj-m target, and feed all
# previously built external exports through one cumulative Module.symvers.
build_audio_module() {
  local public="$1" source_rel="$2" target="$3" modname="$4"
  local source_dir="${AUDIO_ROOT}/${source_rel}"
  local work="${MODULE_WORK}/audio/${public%.ko}"
  local kbuild="${work}/Kbuild"
  local log="${REPORT_DIR}/${public%.ko}.log"

  echo "== Building ${public} from ${source_rel}/${target}.ko =="
  test -d "${source_dir}"
  rm -rf "${work}"
  mkdir -p "${work}"
  rsync -a --exclude='*.o' --exclude='*.ko' --exclude='*.cmd' \
    --exclude='Module.symvers' --exclude='modules.order' \
    "${source_dir}/" "${work}/"
  test -f "${kbuild}"

  python3 - "${kbuild}" "${target}" <<'PY'
from pathlib import Path
import re
import sys
path = Path(sys.argv[1])
target = sys.argv[2]
text = path.read_text()
# Android's helper supplies cross-module symbols externally.  Remove the
# unpublished staging paths and use the cumulative file passed by the script.
text = "\n".join(
    line for line in text.splitlines()
    if "KBUILD_EXTRA_SYMBOLS" not in line
) + "\n"
# Build only the requested LOCAL_MODULE_KBUILD_NAME in this isolated tree.
text = re.sub(r"^\s*obj-[^\n]*$", "", text, flags=re.M)
text += f"\nobj-m += {target}.o\n"
path.write_text(text)
PY

  set +e
  make -j4 -C "${KERNEL_DIR}" O="${OUT_DIR}" M="${work}" \
    AUDIO_ROOT="${AUDIO_ROOT}" \
    MODNAME="${modname}" BOARD_PLATFORM=msmnile CONFIG_SND_SOC_SM8150=m \
    OUT="${AUDIO_ANDROID_OUT}" \
    KBUILD_EXTRA_SYMBOLS="${CUMULATIVE_SYMVERS}" \
    modules 2>&1 | tee "${log}"
  local status=${PIPESTATUS[0]}
  set -e
  if [[ ${status} -ne 0 ]]; then
    echo "${public}: build failed with ${status}" >&2
    return "${status}"
  fi

  test -s "${work}/${target}.ko"
  cp -f "${work}/${target}.ko" "${PACKAGE_DIR}/${public}"
  if [[ -s "${work}/Module.symvers" ]]; then
    cat "${work}/Module.symvers" >> "${CUMULATIVE_SYMVERS}"
    sort -u "${CUMULATIVE_SYMVERS}" -o "${CUMULATIVE_SYMVERS}"
    cp "${work}/Module.symvers" "${REPORT_DIR}/${public%.ko}.Module.symvers"
  fi
}

# Topological order derived from the known-good modules.dep so every consumer
# sees the CRCs exported by providers already rebuilt for 4.14.190.
while IFS='|' read -r public source_rel target modname; do
  [[ -n "${public}" ]] || continue
  build_audio_module "${public}" "${source_rel}" "${target}" "${modname}"
done <<'EOF'
audio_q6_pdr.ko|dsp|q6_pdr_dlkm|q6_pdr_dlkm
audio_q6_notifier.ko|dsp|q6_notifier_dlkm|q6_notifier_dlkm
audio_apr.ko|ipc|apr_dlkm|apr_dlkm
audio_wglink.ko|ipc|wglink_dlkm|wglink_dlkm
audio_q6.ko|dsp|q6_dlkm|q6_dlkm
audio_adsp_loader.ko|dsp|adsp_loader_dlkm|adsp_loader_dlkm
audio_usf.ko|dsp|usf_dlkm|usf_dlkm
audio_pinctrl_wcd.ko|soc|pinctrl_wcd_dlkm|pinctrl_wcd_dlkm
audio_swr.ko|soc|swr_dlkm|swr_dlkm
audio_wcd_core.ko|asoc/codecs|wcd_core_dlkm|wcd_core_dlkm
audio_swr_ctrl.ko|soc|swr_ctrl_dlkm|swr_ctrl_dlkm
audio_wsa881x.ko|asoc/codecs|wsa881x_dlkm|wsa881x_dlkm
audio_wcd9xxx.ko|asoc/codecs|wcd9xxx_dlkm|wcd9xxx_dlkm
audio_mbhc.ko|asoc/codecs|mbhc_dlkm|mbhc_dlkm
audio_wcd_spi.ko|asoc/codecs|wcd_spi_dlkm|wcd_spi_dlkm
audio_stub.ko|asoc/codecs|stub_dlkm|stub_dlkm
audio_hdmi.ko|asoc/codecs|hdmi_dlkm|hdmi_dlkm
audio_platform.ko|asoc|platform_dlkm|platform_dlkm
audio_wcd934x.ko|asoc/codecs/wcd934x|wcd934x_dlkm|wcd934x_dlkm
audio_wcd9360.ko|asoc/codecs/wcd9360|wcd9360_dlkm|wcd9360_dlkm
audio_max98937.ko|asoc/codecs/max989xx|max98937_dlkm|max98937_dlkm
audio_tfa9894.ko|asoc/codecs/tfa9894|tfa9894_dlkm|tfa9894_dlkm
audio_native.ko|dsp/codecs|native_dlkm|native_dlkm
audio_machine_msmnile.ko|asoc|machine_dlkm|machine_dlkm
EOF

# OPlus audio extension is an independent DLKM.  Locate its Kbuild by the
# internal module name recorded in the known-good binary.
extend_kbuild="$(grep -RIl --include=Kbuild --include=Makefile \
  'audio_extend_dlkm' "${VENDOR_ROOT}/oplus" | head -n1 || true)"
test -n "${extend_kbuild}"
extend_source="$(dirname "${extend_kbuild}")"
extend_rel="${extend_source#${AUDIO_ROOT}/}"
if [[ "${extend_source}" == "${AUDIO_ROOT}"/* ]]; then
  build_audio_module audio_extend.ko "${extend_rel}" audio_extend_dlkm audio_extend_dlkm
else
  work="${MODULE_WORK}/audio/audio_extend"
  rm -rf "${work}"
  mkdir -p "${work}"
  rsync -a "${extend_source}/" "${work}/"
  kbuild="${work}/$(basename "${extend_kbuild}")"
  python3 - "${kbuild}" <<'PY'
from pathlib import Path
import re
import sys
path = Path(sys.argv[1])
text = path.read_text()
text = "\n".join(line for line in text.splitlines() if "KBUILD_EXTRA_SYMBOLS" not in line) + "\n"
text = re.sub(r"^\s*obj-[^\n]*$", "", text, flags=re.M)
text += "\nobj-m += audio_extend_dlkm.o\n"
path.write_text(text)
PY
  make -j4 -C "${KERNEL_DIR}" O="${OUT_DIR}" M="${work}" \
    MODNAME=audio_extend_dlkm BOARD_PLATFORM=msmnile \
    KBUILD_EXTRA_SYMBOLS="${CUMULATIVE_SYMVERS}" modules \
    2>&1 | tee "${REPORT_DIR}/audio_extend.log"
  test -s "${work}/audio_extend_dlkm.ko"
  cp -f "${work}/audio_extend_dlkm.ko" "${PACKAGE_DIR}/audio_extend.ko"
  if [[ -s "${work}/Module.symvers" ]]; then
    cat "${work}/Module.symvers" >> "${CUMULATIVE_SYMVERS}"
    sort -u "${CUMULATIVE_SYMVERS}" -o "${CUMULATIVE_SYMVERS}"
  fi
fi

# ColorOS reads the OnePlus 9R subsystem sleep-voter ABI through procfs.  Build
# the hardened OPlus module against the matching kernel and include it in the
# normal DLKM load set.
SLEEPMON_ROOT="${VENDOR_ROOT}/oplus/kernel/power/subsys_sleep_monitor"
sleepmon_work="${MODULE_WORK}/oplus/subsys_sleep_monitor"
test -f "${SLEEPMON_ROOT}/oplus_subsys_sleep_monitor.c"
rm -rf "${sleepmon_work}"
mkdir -p "${sleepmon_work}"
rsync -a --exclude='*.o' --exclude='*.ko' --exclude='*.cmd' \
  --exclude='Module.symvers' --exclude='modules.order' \
  "${SLEEPMON_ROOT}/" "${sleepmon_work}/"
make -j4 -C "${KERNEL_DIR}" O="${OUT_DIR}" M="${sleepmon_work}" \
  CC="${CLANG_DIR}/bin/clang" \
  CONFIG_OPLUS_SUBSYS_SLEEP_MONITOR=m \
  KBUILD_EXTRA_SYMBOLS="${CUMULATIVE_SYMVERS}" modules \
  2>&1 | tee "${REPORT_DIR}/oplus_subsys_sleep_monitor.log"
test -s "${sleepmon_work}/oplus_subsys_sleep_monitor.ko"
cp -f "${sleepmon_work}/oplus_subsys_sleep_monitor.ko" \
  "${PACKAGE_DIR}/oplus_subsys_sleep_monitor.ko"

# Qualcomm qcacld WLAN was already proven buildable directly with Kbuild in the
# source-completeness audit.  Rebuild it against the 4.14.190 output.
WLAN_ROOT="${WLAN_PARENT}/qcacld-3.0"
test -f "${WLAN_ROOT}/Kbuild"
rm -f "${WLAN_ROOT}"/*.o "${WLAN_ROOT}"/*.ko "${WLAN_ROOT}"/Module.symvers "${WLAN_ROOT}"/modules.order
make -j4 -C "${KERNEL_DIR}" O="${OUT_DIR}" M="${WLAN_ROOT}" \
  WLAN_ROOT="${WLAN_ROOT}" \
  WLAN_COMMON_ROOT=../qca-wifi-host-cmn \
  WLAN_COMMON_INC="${WLAN_PARENT}/qca-wifi-host-cmn" \
  WLAN_FW_API="${WLAN_PARENT}/fw-api" \
  WLAN_PROFILE=default MODNAME=wlan BOARD_PLATFORM=msmnile \
  CONFIG_QCA_CLD_WLAN=m \
  KBUILD_EXTRA_SYMBOLS="${CUMULATIVE_SYMVERS}" \
  modules 2>&1 | tee "${REPORT_DIR}/qca_cld3_wlan.log"
test -s "${WLAN_ROOT}/wlan.ko"
cp -f "${WLAN_ROOT}/wlan.ko" "${PACKAGE_DIR}/qca_cld3_wlan.ko"

# Runtime manifest: BinderStats lives in vmlinux; Wave 44 adds the subsystem
# sleep monitor to the existing 32-module DLKM set.
cat > "${MODULE_WORK}/expected-modules.txt" <<'EOF'
audio_adsp_loader.ko
audio_apr.ko
audio_extend.ko
audio_hdmi.ko
audio_machine_msmnile.ko
audio_max98937.ko
audio_mbhc.ko
audio_native.ko
audio_pinctrl_wcd.ko
audio_platform.ko
audio_q6.ko
audio_q6_notifier.ko
audio_q6_pdr.ko
audio_stub.ko
audio_swr.ko
audio_swr_ctrl.ko
audio_tfa9894.ko
audio_usf.ko
audio_wcd934x.ko
audio_wcd9360.ko
audio_wcd9xxx.ko
audio_wcd_core.ko
audio_wcd_spi.ko
audio_wglink.ko
audio_wsa881x.ko
mpq-adapter.ko
mpq-dmx-hw-plugin.ko
msm_11ad_proxy.ko
oplus_subsys_sleep_monitor.ko
qca_cld3_wlan.ko
rdbg.ko
tspp.ko
wil6210.ko
EOF
find "${PACKAGE_DIR}" -maxdepth 1 -type f -name '*.ko' -printf '%f\n' | sort > "${MODULE_WORK}/actual-modules.txt"
sort "${MODULE_WORK}/expected-modules.txt" -o "${MODULE_WORK}/expected-modules.txt"
diff -u "${MODULE_WORK}/expected-modules.txt" "${MODULE_WORK}/actual-modules.txt"
test "$(wc -l < "${MODULE_WORK}/actual-modules.txt")" = 33

# Keep modules uncompressed and strip only non-runtime debug information.
for module in "${PACKAGE_DIR}"/*.ko; do
  "${CLANG_DIR}/bin/llvm-strip" --strip-debug "${module}"
  test -s "${module}"
done

# Validate exact vermagic and collect internal names/dependencies/aliases.
: > "${REPORT_DIR}/vermagic.txt"
: > "${REPORT_DIR}/module-info.txt"
declare -A INTERNAL_TO_PUBLIC=()
for module in "${PACKAGE_DIR}"/*.ko; do
  public="$(basename "${module}")"
  internal="$(modinfo -F name "${module}")"
  vermagic="$(modinfo -F vermagic "${module}")"
  test "${vermagic}" = "${EXPECTED_VERMAGIC}"
  INTERNAL_TO_PUBLIC["${internal}"]="${public}"
  echo "${public}: ${vermagic}" >> "${REPORT_DIR}/vermagic.txt"
  {
    echo "### ${public}"
    modinfo "${module}"
    echo
  } >> "${REPORT_DIR}/module-info.txt"
done

# Preserve the known-good load order while pointing at the newly rebuilt files.
cat > "${PACKAGE_DIR}/modules.load" <<'EOF'
audio_apr.ko
audio_wglink.ko
audio_q6_pdr.ko
audio_q6_notifier.ko
audio_adsp_loader.ko
audio_q6.ko
audio_usf.ko
audio_pinctrl_wcd.ko
audio_swr.ko
audio_wcd_core.ko
audio_swr_ctrl.ko
audio_wsa881x.ko
audio_platform.ko
audio_hdmi.ko
audio_stub.ko
audio_wcd9xxx.ko
audio_mbhc.ko
audio_wcd934x.ko
audio_wcd9360.ko
audio_wcd_spi.ko
audio_native.ko
audio_machine_msmnile.ko
wil6210.ko
msm_11ad_proxy.ko
mpq-adapter.ko
mpq-dmx-hw-plugin.ko
tspp.ko
audio_max98937.ko
audio_tfa9894.ko
audio_extend.ko
oplus_subsys_sleep_monitor.ko
qca_cld3_wlan.ko
rdbg.ko
EOF

python3 - "${PACKAGE_DIR}" <<'PY'
from pathlib import Path
import subprocess
import sys

root = Path(sys.argv[1])
modules = sorted(root.glob('*.ko'))
internal_to_public = {}
for module in modules:
    internal = subprocess.check_output(['modinfo', '-F', 'name', str(module)], text=True).strip()
    internal_to_public[internal] = module.name
    internal_to_public[internal.replace('-', '_')] = module.name

with (root / 'modules.dep').open('w') as out:
    for module in modules:
        depends = subprocess.check_output(['modinfo', '-F', 'depends', str(module)], text=True).strip()
        providers = []
        if depends:
            for dep in depends.split(','):
                dep = dep.strip()
                if not dep:
                    continue
                provider = internal_to_public.get(dep) or internal_to_public.get(dep.replace('-', '_'))
                if provider:
                    providers.append(f'/vendor/lib/modules/{provider}')
        suffix = (' ' + ' '.join(providers)) if providers else ''
        out.write(f'/vendor/lib/modules/{module.name}:{suffix}\n')

with (root / 'modules.alias').open('w') as out:
    out.write('# Aliases extracted from modules themselves.\n')
    for module in modules:
        public = module.stem
        aliases = subprocess.check_output(['modinfo', '-F', 'alias', str(module)], text=True).splitlines()
        for alias in aliases:
            alias = alias.strip()
            if alias:
                out.write(f'alias {alias} {public}\n')

with (root / 'modules.softdep').open('w') as out:
    out.write('# Soft dependencies extracted from modules themselves.\n')
    for module in modules:
        public = module.stem
        softdeps = subprocess.check_output(['modinfo', '-F', 'softdep', str(module)], text=True).splitlines()
        for softdep in softdeps:
            softdep = softdep.strip()
            if softdep:
                out.write(f'softdep {public} {softdep}\n')
PY

# Full binary ABI verification: every imported CRC must be supplied by either
# the 4.14.190 kernel or another module in this package with the same CRC.
sudo apt-get install -y --no-install-recommends python3-pyelftools p7zip-full
python3 - "${PACKAGE_DIR}" "${OUT_DIR}/Module.symvers" "${REPORT_DIR}/MODULE-ABI-REPORT.txt" <<'PY'
from pathlib import Path
from collections import defaultdict
import struct
import sys
from elftools.elf.elffile import ELFFile

root = Path(sys.argv[1])
symvers_path = Path(sys.argv[2])
report_path = Path(sys.argv[3])

kernel = {}
for line in symvers_path.read_text().splitlines():
    fields = line.split('\t')
    if len(fields) >= 2:
        kernel[fields[1]] = int(fields[0], 16) & 0xffffffff

def versions(path):
    with path.open('rb') as f:
        elf = ELFFile(f)
        sec = elf.get_section_by_name('__versions')
        if sec is None:
            return []
        data = sec.data()
        if len(data) % 64:
            raise SystemExit(f'{path.name}: invalid __versions size {len(data)}')
        out = []
        for off in range(0, len(data), 64):
            item = data[off:off + 64]
            crc = struct.unpack('<Q', item[:8])[0] & 0xffffffff
            name = item[8:].split(b'\0', 1)[0].decode('ascii', 'replace')
            out.append((name, crc))
        return out

def exports(path):
    with path.open('rb') as f:
        elf = ELFFile(f)
        symtab = elf.get_section_by_name('.symtab')
        if symtab is None:
            return {}
        return {
            sym.name[6:]: sym['st_value'] & 0xffffffff
            for sym in symtab.iter_symbols()
            if sym.name.startswith('__crc_')
        }

modules = sorted(root.glob('*.ko'))
peer = {}
provider = {}
for module in modules:
    for name, crc in exports(module).items():
        if name in peer and peer[name] != crc:
            raise SystemExit(f'conflicting package exports for {name}')
        peer[name] = crc
        provider[name] = module.name

errors = []
lines = []
for module in modules:
    matched_kernel = matched_peer = 0
    for name, crc in versions(module):
        if name in kernel:
            if kernel[name] != crc:
                errors.append(f'{module.name}: kernel CRC mismatch {name}: {crc:08x} != {kernel[name]:08x}')
            else:
                matched_kernel += 1
        elif name in peer:
            if peer[name] != crc:
                errors.append(f'{module.name}: peer CRC mismatch {name}: {crc:08x} != {peer[name]:08x} ({provider[name]})')
            else:
                matched_peer += 1
        else:
            errors.append(f'{module.name}: unresolved versioned import {name} ({crc:08x})')
    lines.append(f'{module.name}: kernel_matches={matched_kernel} peer_matches={matched_peer}')

report = [
    'Miru 4.14.190 rebuilt external module ABI report',
    '================================================',
    '',
    f'modules={len(modules)}',
    f'errors={len(errors)}',
    '',
    *lines,
]
if errors:
    report.extend(['', 'ERRORS', '------', *errors])
report_path.write_text('\n'.join(report) + '\n')
print(report_path.read_text())
if errors:
    raise SystemExit('external module ABI verification failed')
PY

# Generate hashes, a concise manifest, and both runtime and audit archives.
(
  cd "${PACKAGE_DIR}"
  sha256sum *.ko modules.alias modules.dep modules.load modules.softdep > SHA256SUMS
)
{
  echo "Miru H.40 external module drop-in"
  echo "kernel_release=${KERNEL_RELEASE}"
  echo "kernel_head=$(git -C "${KERNEL_DIR}" rev-parse HEAD)"
  echo "vendor_source_commit=$(git -C "${RUNNER_TEMP}/oneplus-sm8150-vendor-source" rev-parse HEAD)"
  echo "module_count=$(find "${PACKAGE_DIR}" -maxdepth 1 -name '*.ko' | wc -l)"
  echo "vermagic=${EXPECTED_VERMAGIC}"
  echo
  cat "${REPORT_DIR}/vermagic.txt"
} > "${REPORT_DIR}/BUILD-MANIFEST.txt"

RUNTIME_ARCHIVE="${ANDROID_ROOT}/out/miru-v3-modules-dropin-4.14.190.7z"
AUDIT_ARCHIVE="${ANDROID_ROOT}/out/miru-v3-modules-dropin-4.14.190-audit.zip"
rm -f "${RUNTIME_ARCHIVE}" "${AUDIT_ARCHIVE}"
(
  cd "${PACKAGE_DIR}"
  7z a -t7z -mx=9 "${RUNTIME_ARCHIVE}" \
    ./*.ko modules.alias modules.dep modules.load modules.softdep >/dev/null
)
python3 - "${AUDIT_ARCHIVE}" "${PACKAGE_DIR}" "${REPORT_DIR}" <<'PY'
from pathlib import Path
import sys
import zipfile
archive = Path(sys.argv[1])
package = Path(sys.argv[2])
reports = Path(sys.argv[3])
with zipfile.ZipFile(archive, 'w', compression=zipfile.ZIP_DEFLATED) as z:
    for path in sorted(package.iterdir()):
        if path.is_file():
            z.write(path, Path('dropin') / path.name)
    for path in sorted(reports.rglob('*')):
        if path.is_file():
            z.write(path, Path('reports') / path.relative_to(reports))
PY

cp "${RUNTIME_ARCHIVE}" "${PACKAGE_DIR}/../miru-v3-modules-dropin-4.14.190.7z"
cp "${AUDIT_ARCHIVE}" "${PACKAGE_DIR}/../miru-v3-modules-dropin-4.14.190-audit.zip"

{
  echo "result=SUCCESS"
  echo "kernel_release=${KERNEL_RELEASE}"
  echo "module_count=33"
  echo "metadata_count=4"
  echo "runtime_archive_sha256=$(sha256sum "${RUNTIME_ARCHIVE}" | awk '{print $1}')"
  echo "audit_archive_sha256=$(sha256sum "${AUDIT_ARCHIVE}" | awk '{print $1}')"
  echo "runtime_archive_size=$(stat -c %s "${RUNTIME_ARCHIVE}")"
  echo "audit_archive_size=$(stat -c %s "${AUDIT_ARCHIVE}")"
} | tee "${REPORT_DIR}/PACKAGE-SUMMARY.txt"

echo "All 33 external modules rebuilt and packaged successfully."
