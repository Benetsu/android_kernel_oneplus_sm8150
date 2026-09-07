# Wave 30.1: 9R healthinfo normalization on proven Wave 29.1

Wave 30 records the two donor-named healthinfo options selected by both
authoritative OnePlus 9R Android 14 Kona configurations directly in the
reconstructed production H.40 configuration:

- `CONFIG_OPLUS_JANK_INFO` enables per-task `/proc/<pid>/jank_info`
  accounting for runnable, running, I/O-wait, binder, futex, mutex, rwsem,
  and other scheduler latency;
- `CONFIG_OPLUS_MEM_MONITOR` connects the existing page-allocation wait hook
  to `/proc/oplus_healthinfo/alloc_wait` and the memory-monitor thresholds.

The Miru tree already contains the matching task fields, fork initialization,
scheduler transition hooks, proc registration, page-allocation timing hook,
and 4.14-adapted external healthinfo implementation. The normal and
performance SM8150 defconfigs already enable both options. The production H.40
configuration also carried the legacy `CONFIG_OPPO_JANK_INFO` and
`CONFIG_OPPO_MEM_MONITOR` compatibility aliases, which select the same Oplus
options. Therefore Wave 30 is explicit configuration normalization and ABI
documentation, not a newly activated runtime path. Both monitors are
reporting/control features and do not change scheduler placement or
memory-reclaim policy.

Wave 30.1 applies only this original Wave 30 configuration/documentation
delta on top of the phone-proven Wave 29.1 boundary. It deliberately excludes
Wave 31 and later ordered-UX work so boot testing can isolate Wave 30.
