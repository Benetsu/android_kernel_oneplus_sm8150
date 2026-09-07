# Wave 31.5: corrected 9R ION boost pool on proven Wave 30.1

Wave 31.5 enables `CONFIG_OPLUS_ION_BOOSTPOOL` directly on the phone-proven
Wave 30.1 source commit `156b229b7c6255fd58640308fbe1b7dc55f0ae6f`.
This retains the Wave 28.1 `init_task.ux_entry` initialization that was absent
from the earlier Wave 31 lineage and preserves the phone-proven Wave 29.1 and
Wave 30.1 changes.

The valid Wave 31.1 corrections are retained: the ION heap device pointer is
initialized before pool creation, page-pool creation is checked before use,
page metadata is returned through its originating allocator, worker shutdown
is safe on partial creation failure, and large-memory watermarks match the
Android 14 OnePlus 9R donor at 128 MiB cached camera plus 64 MiB uncached.

Additional corrections in this rebase:

- accept both NULL and error-pointer boost allocation failures before
  dereferencing page metadata;
- make the external allocator return NULL consistently on allocation failure;
- create the shared page-metadata slab before starting either boost worker;
- create the uncached reserve before the camera reserve, matching donor order;
- ignore the allocator-service fast path until its TGID has actually been
  discovered; and
- guard worker pointers in the shrinker.

The build workflow performs the normal compile and packaging path without
adding a separate source verifier. Phone validation remains required because
the earlier green Wave 31 builds proved compilation alone cannot establish
early-boot safety.

Status: `wave31-5-source-prepared`.