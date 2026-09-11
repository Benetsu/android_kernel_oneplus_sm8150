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

Clock-plan indices are resolved from version 1.0 DDR AOP SMEM item 604.  H.40
XBL also publishes the item's physical address in the bounded ten-entry AOP
message-RAM SMEM table at section `0xE`.  Wave 44.2 uses that authoritative
address as a fallback when Linux's normal global-SMEM lookup cannot see the
allocation.  The address must remain inside the device-tree reserved SMEM
region, and the version, table offsets, sizes, and 40-byte records are still
strictly validated.  Wave 44.3 exposed the live item header and established
that H.40 supplies split-u16 version 1.1 with five table descriptors.  The item
is 1033 bytes: its MC table is 520 bytes at offset 24 (13 records), its SHUB
table is 320 bytes at offset 544 (8 records), and the three following tables
end exactly at the item boundary.  Wave 44.4 accepts that backward-compatible
layout only after validating all five ordered spans.  Version 1.0 remains
supported for related firmware.  Invalid data never produces guessed
frequencies.

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

`clock_plans` also reports whether the normal SMEM API or the AOP/XBL address
table supplied the mapping, preserves both lookup status codes, and includes
the bounded raw header bytes needed to diagnose another firmware revision
without enabling `/dev/mem`.

Success requires the ABI marker, nonzero MC and SHUB frequency plans, monotonic
transition timestamps, `FREQ_DONE` records after memory-load changes, and
increasing manager counters. Repeated reads must not produce dictionary or
unstable-snapshot errors.

The existing H.O.2.0 `qcom,ddr-stats` implementation remains in the kernel for
device trees that genuinely select it. All reconstructed H.40 variants select
`qcom,h40-ddr-stats` and pointer slot `0x0c3f0014` instead.
