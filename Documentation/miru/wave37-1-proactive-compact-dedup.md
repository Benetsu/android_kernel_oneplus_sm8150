# Miru H.40 Wave 37.1: proactive-compact early-boot fix

Wave 37.1 retains the authoritative OnePlus 9R Android 14 implementation of
`/proc/oplus_mem/fragmentation_index` from the external source tree and removes
the older Miru compatibility copy from `fs/proc`.

Both copies were previously built into the kernel as
`oplus_bsp_proactive_compact` and registered identically named built-in module
parameters:

- `compaction_hpage_order`
- `compaction_proactiveness`

The duplicate parameter attributes made the 4.14 built-in parameter sysfs
setup fail at `subsys_initcall` time, before either TWRP or Android userspace
could start. Wave 37.1 leaves exactly one provider:

`CONFIG_PROACTIVE_COMPACT=y`

The public proc ABI and its 9R behavior remain unchanged.
