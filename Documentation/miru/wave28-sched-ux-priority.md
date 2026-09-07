# Wave 28: Android 14 ordered UX priority scheduling

Wave 28 ports the complete `CONFIG_OPLUS_FEATURE_SCHED_UX_PRIORITY` path from
the authoritative OnePlus 9R Android 14 kernel and external-module sources.
This is a scheduler-behaviour wave, not a new pathname-only ABI wave.

The 9R implementation replaces the older vruntime-bias/list-pick path with a
per-runqueue ordered UX list. It adds:

- explicit priority bits in the existing per-task `ux_state` control;
- ordered enqueue/dequeue and fair-class next-task replacement;
- wakeup-preemption decisions between UX and non-UX tasks;
- four-millisecond execution slices with donor per-type budgets;
- inherited and one-shot UX expiry handling;
- optional per-CPU priority trace markers through the existing debug gate.

The port includes every matching core-scheduler call site, the task and
runqueue state, fork initialization, rq-locked state transitions, and the
matching external `sched_assist` implementation. The old placement and pick
helpers remain compiled as the disabled-config fallback, but are not run when
ordered priority scheduling is selected.

`CONFIG_OPLUS_FEATURE_SCHED_UX_PRIORITY` is enabled in both Miru SM8150
defconfigs and the reconstructed H.40 build configuration, matching both 9R
Kona production configurations. No DLKM is added; the implementation remains
built into the existing sched_assist path.

Build run `34056641894` passed the kernel and all reconstructed H.40 DTB/DTBO
targets, the matching 32 external modules, packaging, and artifact upload at
kernel commit `3d108d708e04807d862ef957dff6b1d43681f559` and external
commit `ea54edf85f7f75493ac555cbc729b343cb822da3`. Artifact
`miru-h40-wave28-sched-ux-priority-kernel-and-modules` (`9996592756`) has
GitHub digest
`sha256:5dbf549f5eff3f00fb985058666c63de871bd1050b601f7d630292d8d04eb803`.
