# Miru H.40 Wave 37.2: charger configfs probe hook

Wave 37.2 makes the charger ABI added in Waves 33 through 37 reachable on the
SM8150 H.40 runtime.

## Runtime finding

Wave 37.1 booted successfully and contained `oplus_chg_configfs_init()`, the
battery attribute handlers, and the `mutual_cmd` handlers in the built-in
kernel.  Nevertheless, `/sys/class/oplus_chg` was absent because the SM8150
SMB5 probe never called the initializer.  The charger core itself continued to
run, confirming that this was a missing probe hook rather than a charger probe
failure.

## Donor-parity fix

The Android 14 OnePlus 9R SM8250 charger probe calls
`oplus_chg_configfs_init(oplus_chip)` after optional USB-temperature thread
initialization.  Wave 37.2 adds the same header and call at the corresponding
point in the H.40 SM8150 probe.

The hook does not change charging policy.  It publishes the read-only battery
telemetry attributes and the fail-open `common/mutual_cmd` compatibility
mailbox already implemented by the preceding waves.

## Expected runtime interface

After boot, `/sys/class/oplus_chg/battery` must contain the Wave 33 through 36
attributes documented in `sysfs-class-oplus-chg-power-stats`, and
`/sys/class/oplus_chg/common/mutual_cmd` must exist.  Reading `mutual_cmd` is a
blocking mailbox operation and must not be used as a simple text-node test.
