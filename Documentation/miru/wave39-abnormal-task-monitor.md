# Miru H.40 Wave 39: OPLUS abnormal-task monitor

Wave 39 restores the OnePlus 9R Android 14 abnormal-task ABI and its complete
scheduler integration:

- `/proc/task_overload/abnormal_task`
- `/proc/task_overload/skip_goplus_enabled`

This is a production donor interface. The authoritative 9R kernel enables
`CONFIG_OPLUS_FEATURE_ABNORMAL_FLAG`, the shipped 9R boot image contains both
proc names and the shipped ColorOS power-stats implementation references
`/proc/task_overload/abnormal_task`. The shipped ODM init policy also assigns
the report node for its ColorOS consumer.

The port retains the donor's task field, fork initialization, bounded report,
CPU/frequency/utilization checks and scheduler placement hooks. Monitoring is
active after boot, while placement restriction remains disabled by default
through `skip_goplus_enabled=0`, matching the donor implementation. ColorOS can
enable the restriction through the existing control node when its policy calls
for it.

This is not a synthetic compatibility node. The scheduler hooks are necessary
to populate the report and to implement the donor's optional GOPLUS placement
policy. The code is built in so the proc ABI exists before its ODM and power
statistics consumers start.
