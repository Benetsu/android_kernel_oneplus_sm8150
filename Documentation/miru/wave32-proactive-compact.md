# Miru H.40 Wave 32: OSense proactive-compaction ABI

Wave 32 restores the OnePlus 9R Android 14 proactive-compaction telemetry
interface required by the ported OSense memory policy:

`/proc/oplus_mem/fragmentation_index`

The implementation is taken from the authoritative 9R external source and is
wired into the Miru kernel at the same `mm/proactive_compact` location used by
the donor. It is built in with `CONFIG_PROACTIVE_COMPACT=y`, so the interface
exists before Android system services begin querying it.

Reading the node returns three decimal fields:

1. whether node 0 currently exceeds the weighted fragmentation watermark;
2. the page order used to score suitable free blocks (default `4`);
3. the proactiveness value used to derive the watermark (default `20`).

The node is policy telemetry. Reading it does not compact memory. Writes only
change the two scoring parameters, matching the donor ABI.

Wave 37.1 removed an older in-tree compatibility implementation which had
accidentally remained enabled alongside this donor implementation. Both
objects used the same built-in module identity and parameter names, causing a
duplicate sysfs-parameter failure during early kernel initialization. The 9R
external implementation and its `CONFIG_PROACTIVE_COMPACT=y` wiring are the
sole provider after that correction.
