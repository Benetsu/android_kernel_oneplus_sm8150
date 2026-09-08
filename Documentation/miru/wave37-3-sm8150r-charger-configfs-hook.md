# Miru H.40 Wave 37.3: SM8150R charger configfs hook

Wave 37.2 proved boot-safe but did not publish `/sys/class/oplus_chg` on the
connected H.40 device. Runtime configuration inspection confirmed that H.40
selects `CONFIG_OPLUS_SM8150R_CHARGER`, whose build target is
`oplus_battery_msm8150Q.c`, rather than the non-R SM8150 target hooked in Wave
37.2.

Wave 37.3 applies the same Android 14 OnePlus 9R probe sequence to the selected
SM8150R implementation: include `oplus_configfs.h` and call
`oplus_chg_configfs_init(oplus_chip)` after optional USB-temperature thread
initialization. No charger control or mailbox semantics change.

For universal H.40 coverage, the same hook is retained in all three selectable
SM8150 charger targets: `SM8150`, `SM8150R`, and `SM8150_PRO`. The separate
`oplus_battery_msm8150Q_pro.c` source is not wired into the Makefile or Kconfig
and remains untouched.
