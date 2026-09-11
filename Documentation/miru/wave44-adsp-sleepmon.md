# Wave 44: DSP sleep visibility and FastRPC PM control

Wave 44 restores two Android 14 OnePlus 9R interfaces that the ported ColorOS
stack demonstrably requests on Miru H.40.

## Confirmed gaps

- ColorOS `QcomSubSystemLpmParser` reads
  `/proc/subsys_sleepmon/adsp_compact`; the Wave 43 runtime reported that the
  file did not exist.
- The ported `sscrpcd` sends FastRPC control request 5 with a 5 ms timeout. The
  older SM8150 driver returned `EBADRQC`, producing repeated `kernel does not
  support PM management` messages.

## Implementation

- Package a hardened version of the official 9R
  `oplus_subsys_sleep_monitor` module and load it automatically with the DLKM
  set. It publishes detailed and compact ADSP, CDSP and SLPI views.
- Preserve the donor SMEM ABI: low-power descriptions are item 590 and live
  voters are item 591 for Qualcomm hosts 2, 5 and 3 respectively.
- Validate every SMEM size and firmware-supplied count, copy each pair of
  tables before formatting, and bound every firmware string. Missing or
  incompatible firmware data returns an error without dereferencing or
  changing it.
- Remove two defects in the donor implementation: subsystem reports no longer
  consult the ADSP globals for CDSP/SLPI, and printing can no longer overwrite
  `normalTimerTid` in shared memory.
- Add the 9R `FASTRPC_CONTROL_PM` request and timeout payload to the existing
  FastRPC ioctl ABI. A request is accepted only after that file enabled kernel
  wakelock control, is capped at 50 ms, validates the selected DSP channel, and
  applies a timed wakeup event to the existing secure/non-secure wake source.
- Retain the proven SM8150 per-invocation stay-awake/relax path unchanged.

## H.40 firmware fallback

Live Wave 44.1 testing confirmed that H.40 does not allocate the newer 9R
SMEM voter records 590 and 591.  Wave 44.2 therefore keeps all recognised
ColorOS compact-parser fields empty rather than inventing blocker names, and
adds truthful, parser-ignored diagnostics sourced from the existing SM8150
RPMh master statistics: `source`, `master`, `sleep_time_ms`, and the original
voter-SMEM error.  The full node states explicitly that per-client voter data
is unavailable on this firmware.

The module is kept external like the 9R donor.  It is placed first in the
generated `modules.load` list because the H.40 loader did not reach it after
optional hardware modules; a manual load proved its vermagic and initializer
were correct.

The newer Qualcomm RPMSG sleep-monitor driver is intentionally not included:
the pristine H.40 firmware does not expose its `sleepmonglink-apps-adsp`
service. This wave adds no DTB/DTBO change, polling loop, panic/SSR control,
sleep-policy override, or printk stream.

## Runtime validation

After installing the matching Wave 44 kernel and 33-module DLKM payload:

```
cat /proc/subsys_sleepmon/adsp_compact
cat /proc/subsys_sleepmon/slpi_compact
cat /proc/subsys_sleepmon/cdsp_compact
logcat -b all -d | grep -F "kernel does not support PM management"
```

Success means the six proc files exist, available firmware tables produce
bounded key/value reports, H.40 fallback reads produce increasing RPMh sleep
totals without fabricated blocker values, and new `sscrpcd` request-5 calls no
longer return `Invalid request code`.
