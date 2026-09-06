# Wave 30: 9R healthinfo configuration normalization

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

Wave 30 run `34064447569` passed kernel plus reconstructed H.40 DTB/DTBO
compilation, the matching 32 external modules, packaging, and artifact upload
at kernel commit `03d47a1334b2ded2bc6c72fd5c0b55cd615ab88e` and external
commit `3fe5933901e630913913ffa8614b59502a13a51f`. Artifact
`miru-h40-wave30-healthinfo-monitoring-kernel-and-modules` (`9998738440`) is
566180747 bytes and has GitHub digest
`sha256:e4445b50c17817bcebed3babd6dc4caca5af6e751cf47048dc777fc33402cc35`.

Status: `wave30-build-verified`.
