# Wave 43: RPMh master residency

Wave 43 makes the Android 14 OnePlus 9R RPMh statistics path an explicit
production feature on Miru H.40. ColorOS probes
`/sys/power/rpmh_stats/master_stats`; earlier runtime logs recorded a failed
read even though the H.40 device tree contains the required
`qcom,rpmh-master-stats-v1` resource at `0x0b221200`.

## Implementation

- Select `CONFIG_QTI_RPM_STATS_LOG` explicitly without enabling debugfs. The
  OPLUS version of these drivers publishes production sysfs attributes.
- Build both `rpm_stats.o` and `rpmh_master_stat.o` from that dedicated option
  instead of selecting them implicitly through the broader RPMh API.
- Keep the SM8150 `get_sleep_exit_time()` consumer and add the donor's bounded
  `get_rpmh_deep_sleep_info()` interface for AOSS and CX accumulated residency.
- Add the donor master-residency helper with SMEM record-size validation.
- Make system-sleep sysfs publication transactional: a failed attribute or
  persistent mapping now fails probe and unwinds all allocations rather than
  leaving a partial ABI behind.
- Document the four existing ColorOS-facing sysfs attributes.

The reconstructed H.40 RPM and RPMh-master resources are retained unchanged.
This wave does not add the optional `/sys/power/soc_sleep/stats` probe path,
enable debugfs, modify cpuidle or suspend policy, or invent DDR firmware data.

## Validation

After boot and after at least one screen-off suspend/resume cycle:

```
cat /sys/power/rpmh_stats/master_stats
cat /sys/power/rpmh_stats/oplus_rpmh_master_stats
cat /sys/power/system_sleep/stats
cat /sys/power/system_sleep/oplus_rpmh_stats
```

Success requires all four reads to succeed, APSS/system-sleep counts to advance
after a real deep-sleep cycle, durations to be monotonic, and the ColorOS RPMh
service to stop reporting a failed read of `rpmh_stats/master_stats`.
