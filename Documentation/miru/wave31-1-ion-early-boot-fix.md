# Wave 31.1: ION boost-pool early-boot correction

Wave 31 compiled successfully but could not reach TWRP ADB or Android
`post-fs` on project 18821. Persistent OP2 logging remained empty and pstore
contained only the preceding Wave 23 recovery session, placing the failure in
the kernel/DTB early-boot path.

Wave 31.1 keeps boost-pool support enabled and corrects the activated 4.14 ION
path instead of disabling the feature:

- initialize `heap->heap.priv` before creating page and boost pools, matching
  the authoritative OnePlus 9R Android 14 system-heap initialization order;
- check `ion_page_pool_create()` before touching the returned pool;
- release boost-pool page metadata through its originating slab cache;
- make both boost workers stoppable and stop the first worker if creation of
  the second worker fails;
- use the Android 14 9R large-memory watermark of 128 MiB cached camera plus
  64 MiB uncached instead of the stale 192 MiB camera value.

The build is based on the exact successful Wave 31 source commit
`52e4ea3db867edd3fb602a6a5a6442ea16901e9e` plus its green-build
documentation commit `9954470ac2fe7b50bef81042e677494db62fd711`.
The matching external source starts from the Wave 31 build input
`3fe5933901e630913913ffa8614b59502a13a51f`; the hardened boost-pool worker
commit is `9d0300392c13711320425926d37c9c6141ebf8bd`.

Phone validation must start with TWRP. Recovery ADB and a Wave 31.1 kernel
banner in pstore are required before attempting an Android boot.

Wave 31.1 run `34074370461` passed kernel plus reconstructed H.40 DTB/DTBO
compilation, all 32 matching external modules, packaging, and artifact upload
at kernel source commit `94ad0d7d1f683a436fa2c80ced4710f4cee3c596` and external
commit `9d0300392c13711320425926d37c9c6141ebf8bd`. Artifact
`miru-h40-wave31-1-ion-fix-kernel-and-modules` (`10002023006`) is 566304417
bytes and has GitHub digest
`sha256:29e40c403f39b93c7f76c910551e327c34b7f0889b3fa687085fceafec93617c`.

Status: `wave31-1-build-verified`; phone boot validation remains pending.
