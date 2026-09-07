# Wave 31: 9R ION boost-pool parity

Both authoritative OnePlus 9R Android 14 Kona configurations enable
`CONFIG_OPLUS_ION_BOOSTPOOL`; the inherited H.40 production configuration
explicitly disabled it. Wave 31 enables the already reconstructed 4.14 ION
boost-pool implementation and its complete hook chain in all Miru SM8150
configurations.

The feature adds cached camera and uncached system-heap reserve pools, connects
their allocation/free/shrinker paths to the existing ION system heap, and
publishes control and status under `/proc/boost_pool`. On devices with more
than 4 GiB of RAM the Android 14 9R donor policy uses a 128 MiB camera low watermark and a
64 MiB uncached low watermark; smaller-memory targets use 32 MiB for each.
The pool is enabled by default, remains reclaimable through the ION shrinker,
and can be stopped or resized through its proc controls.

Wave 31 run `34065740351` passed kernel plus reconstructed H.40 DTB/DTBO
compilation, the matching 32 external modules, packaging, and artifact upload
at kernel commit `52e4ea3db867edd3fb602a6a5a6442ea16901e9e` and external
commit `3fe5933901e630913913ffa8614b59502a13a51f`. Artifact
`miru-h40-wave31-ion-boost-pool-kernel-and-modules` (`9999283213`) is
566307061 bytes and has GitHub digest
`sha256:61f6b73f62a7019d2aef4e3f2dc4a10cc53b5d0b5075fcbfaeb7db0d6d602e74`.

Status: `wave31-build-verified`.

Phone testing subsequently showed that this build could not reach either
TWRP ADB or Android `post-fs`. See
`Documentation/miru/wave31-1-ion-early-boot-fix.md` for the corrected donor
integration and early-boot isolation build.
