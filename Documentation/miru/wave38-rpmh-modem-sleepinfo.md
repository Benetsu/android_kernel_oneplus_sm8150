# Miru H.40 Wave 38: RPMh modem sleepinfo buffer

Wave 38 restores the production OnePlus 9R Android 14 power-monitoring ABI:

`/proc/rpmh_modem/sleepinfo`

This is not an inferred node. The authoritative 9R main-kernel source builds
`drivers/soc/qcom/rpmh_modem_sleepinfo.c` by default, the shipped 9R boot image
contains the provider, and the shipped ColorOS stack contains all three
matching consumers/configuration points:

- `odm/bin/qmi-framework-tests/qmi_master_stats_service` writes reports and
  uses `OPLUS_MARK_RESTART`;
- `system_ext/etc/init/init.oplus.rootdir.rc` assigns mode `0666` and
  `system:system` ownership;
- the vendor SELinux policy labels the proc node `opppo_powermonitor`.

The external 9R wakelock profiler also links against the provider's exported
`rpmh_modem_sleepinfo_buffer_clear()` helper when RPMh power monitoring is
enabled.

The implementation is a passive, bounded 100 KiB text buffer. It does not
touch RPMh registers, SMEM, firmware, clocks, regulators, or device-tree data,
so it is portable to SM8150 without importing Kona hardware assumptions.
`CONFIG_RPMH_MODEM_SLEEPINFO_BUFFER=y` keeps it built in, matching the donor's
default and making the node available before ColorOS starts its writer.
