# Wave 42: SM8150 standby attribution

Wave 42 restores the OnePlus wakelock profiler's platform attribution on the
H.40 SM8150 family. It is based on the proven Wave 41 source and follows the
Android 14 OnePlus 9R implementation split between the main kernel and the
external-module repository.

## Problem

The H.40 configuration selected `CONFIG_OPLUS_POWER_QCOM`, which compiles the
old fixed Atoll table from the donor external tree. That backend cannot match
SM8150 wake IRQ names. The Android 14 9R configuration instead leaves that
legacy selector disabled and builds the generic device-tree-selected profiler.
Consequently the profiler nodes existed on Miru, but wake counts were commonly
reported as zero or attributed to the wrong category.

## Implementation

- Keep `CONFIG_OPLUS_WAKELOCK_PROFILER=y`, but disable the obsolete fixed Atoll
  backend so the generic profiler reads the root `qcom,sm8150` compatible.
- Add an SM8150 platform table in external source commit
  `1fff319cb57878a3c61ece6733d7da7b87fa9095`.
- Match both modem layouts supported by the universal kernel:
  - guacamole and the other non-SDX55 projects use the integrated modem paths;
  - hotdogg (project 19861) additionally uses the SDX55/MHI wake names observed
    on the running device: `mhi`, `mdm status`, and `mdm errfatal`.
- Count the aggregate `glink` wake category from GIC resume IRQ names, matching
  the 9R intent without importing its newer IPCC driver into SM8150.
- Count suspend aborts whenever standby profiling is enabled. Diagnostic log
  verbosity remains controlled separately by the debug option.
- Demote the generic profiler's per-match message to debug level so accounting
  does not itself create a wake-log stream.

No cpuidle, RPMh, suspend-policy, firmware, modem-control, or device-tree
behavior is changed by this wave.

## Runtime validation

After at least one screen-off suspend/resume cycle:

```
cat /sys/kernel/wakelock_profiler/ap_resume_reason_stastics
cat /sys/kernel/wakelock_profiler/modem_resume_reason_stastics
cat /sys/kernel/wakelock_profiler/kernel_time
cat /sys/kernel/wakelock_profiler/active_max
```

Success means the directory and all four attributes exist, `wakeup_sum`
increases after real resumes, power-key/RTC wakes enter their named categories,
and the modem category records the applicable integrated-modem or SDX55/MHI
source without continuous kernel-log output. Resettable attributes continue to
accept the donor command `reset`.
