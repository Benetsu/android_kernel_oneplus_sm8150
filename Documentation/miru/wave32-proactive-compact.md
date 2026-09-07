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

This closes a runtime/documentation discrepancy: the path was already present
in Miru's ABI document, while the Wave 31.5 phone repeatedly logged that it did
not exist and OSense therefore treated memory as not fragmented.
