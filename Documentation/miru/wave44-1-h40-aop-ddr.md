# Wave 44.1: H.40 AOP DDR transition decoder

## Purpose

Wave 44.1 corrects two independent issues:

- Wave 44's new subsystem sleep-monitor module was accidentally compiled with
  the host GCC. The build now passes the pinned Android Clang executable
  explicitly for that module.
- The Wave 16/23 DDR reader used the OnePlus 9R AOP H.O.2.0 ABI. H.40 uses an
  older but functional H.O.1.1 message-RAM ABI, now decoded separately.

## Firmware ABI

H.40 publishes an offset at physical address `0x0c3f0014`. The expected value
is `0x000b0000`, selecting a 1 KiB page at `0x0c3b0000` relative to the AOP
message-RAM base `0x0c300000`.

The driver refuses to bind unless the offset is aligned and bounded and the
page dictionary is exactly:

```text
event offset = 0x10
event count  = 50
stats offset = 0x350
config offset = 0x330
```

The records are copied twice and accepted only when both snapshots match.
This prevents a partially updated AOP record from being decoded.

Clock-plan indices are resolved from version 1.0 DDR AOP SMEM item 604. An
invalid SMEM table never produces guessed frequencies; the driver continues
to expose raw indices and reports zero for unavailable mappings.

## Exposed diagnostics

```text
/sys/power/ddr/abi
/sys/power/ddr/transitions
/sys/power/ddr/recent_residency
/sys/power/ddr/manager_stats
/sys/power/ddr/clock_plans
```

`recent_residency` covers only completed intervals present in the 50-record
ring. It intentionally does not create `/sys/power/ddr/residency`, because the
9R name denotes cumulative firmware-maintained lifetime data and H.40 does not
publish that table.

## Runtime validation

```text
cat /sys/power/ddr/abi
cat /sys/power/ddr/clock_plans
cat /sys/power/ddr/manager_stats
cat /sys/power/ddr/transitions
cat /sys/power/ddr/recent_residency
```

Success requires the ABI marker, nonzero MC and SHUB frequency plans, monotonic
transition timestamps, `FREQ_DONE` records after memory-load changes, and
increasing manager counters. Repeated reads must not produce dictionary or
unstable-snapshot errors.

The existing H.O.2.0 `qcom,ddr-stats` implementation remains in the kernel for
device trees that genuinely select it. All reconstructed H.40 variants select
`qcom,h40-ddr-stats` and pointer slot `0x0c3f0014` instead.
