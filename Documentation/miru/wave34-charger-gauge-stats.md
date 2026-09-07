# Miru H.40 Wave 34: charger gauge statistics

Wave 34 completes the safe read-only subset of the 9R battery statistics ABI
whose values already exist in H40's active charger core:

- `/sys/class/oplus_chg/battery/authenticate`
- `/sys/class/oplus_chg/battery/battery_cc`
- `/sys/class/oplus_chg/battery/battery_fcc`
- `/sys/class/oplus_chg/battery/battery_soh`

The port uses the same `oplus_chg_chip` fields as the 9R donor and extends the
fail-open battery class device added by Wave 33. It does not add writable
charging controls or alter gauge calculations.

These paths are directly referenced by the ported ColorOS 14 charger service,
power.stats HAL, PowerMonitor, and Midas. The userspace-only `battery_dod` probe
is deliberately excluded because no matching 9R OSS producer exists in either
authoritative kernel repository.
