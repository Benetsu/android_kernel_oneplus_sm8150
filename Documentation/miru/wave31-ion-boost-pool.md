# Wave 31: 9R ION boost-pool parity

Both authoritative OnePlus 9R Android 14 Kona configurations enable
`CONFIG_OPLUS_ION_BOOSTPOOL`; the inherited H.40 production configuration
explicitly disabled it. Wave 31 enables the already reconstructed 4.14 ION
boost-pool implementation and its complete hook chain in all Miru SM8150
configurations.

The feature adds cached camera and uncached system-heap reserve pools, connects
their allocation/free/shrinker paths to the existing ION system heap, and
publishes control and status under `/proc/boost_pool`. On devices with more
than 4 GiB of RAM the donor policy uses a 192 MiB camera low watermark and a
64 MiB uncached low watermark; smaller-memory targets use 32 MiB for each.
The pool is enabled by default, remains reclaimable through the ION shrinker,
and can be stopped or resized through its proc controls.

Status: `wave31-implemented-locally-pending-ci`.
