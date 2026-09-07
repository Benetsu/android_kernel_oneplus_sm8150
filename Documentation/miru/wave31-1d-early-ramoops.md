# Wave 31.1D early-ramoops diagnostic

This branch is based on the all-green Wave 31.1 ION fix. It adds temporary
diagnostics only; it does not change ION allocation policy or pool behavior.

The shipped H.40 ramoops range at `0xA9800000` (4 MiB) is instantiated at the
first initcall level rather than waiting for DT platform population. Initcall
entry/return lines are raised to notice level and enabled by default so the
persistent console retains the last completed boundary. Explicit emergency
markers surround system-heap, normal page-pool, camera boost-pool, and
uncached boost-pool creation.

Expected recovery evidence after a failed boot is `/sys/fs/pstore/console-ramoops-0`.
The later DT ramoops probe may report `already initialized`; that is expected
because only one backend can own the shipped persistent range.

All changes in this commit are diagnostic and must be removed after isolation.