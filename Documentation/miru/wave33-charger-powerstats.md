# Miru H.40 Wave 33: charger power-statistics ABI

Wave 33 restores the two read-only Oplus charger attributes that the ColorOS 14
power-statistics HAL requests on the running OnePlus 7 Pro:

- `/sys/class/oplus_chg/battery/battery_rm`
- `/sys/class/oplus_chg/battery/chip_soc`

Both values already exist in H40's active `oplus_chg_chip` as `batt_rm` and
`soc`. The change publishes those existing values through the donor-compatible
`oplus_chg/battery` class device; it does not change charging policy, capacity
calculation, thermal limits, or hardware programming.

Battery-device creation is fail-open for boot: allocation or attribute errors
are logged while the pre-existing wireless class initialization continues.
