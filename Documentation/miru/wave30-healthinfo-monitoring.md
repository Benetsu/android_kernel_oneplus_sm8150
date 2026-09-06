# Wave 30: 9R healthinfo monitoring completion

Wave 30 enables the two remaining healthinfo monitors selected by both
authoritative OnePlus 9R Android 14 Kona configurations:

- `CONFIG_OPLUS_JANK_INFO` enables per-task `/proc/<pid>/jank_info`
  accounting for runnable, running, I/O-wait, binder, futex, mutex, rwsem,
  and other scheduler latency;
- `CONFIG_OPLUS_MEM_MONITOR` connects the existing page-allocation wait hook
  to `/proc/oplus_healthinfo/alloc_wait` and the memory-monitor thresholds.

The Miru tree already contains the matching task fields, fork initialization,
scheduler transition hooks, proc registration, page-allocation timing hook,
and 4.14-adapted external healthinfo implementation. The normal and
performance SM8150 defconfigs already enable both options; this wave closes
the gap in the reconstructed production H.40 configuration used by CI and
device images. Both monitors are reporting/control features and do not change
scheduler placement or memory-reclaim policy.

Status: `wave30-implemented-locally-pending-ci`.
