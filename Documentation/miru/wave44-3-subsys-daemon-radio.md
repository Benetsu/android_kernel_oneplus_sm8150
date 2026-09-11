# Wave 44.3 investigation: hotdogg subsys_daemon abort

## Result

The repeatable `subsys_daemon` restart is not caused by the Wave 44 DDR or
sleep-monitor kernel work.  It is a userspace QMI response-layout mismatch
between the OnePlus 9R ColorOS 14 radio library and hotdogg's older modem
firmware.

The process starts as:

```text
/odm/bin/hw/subsys_daemon -l /odm/lib64/libqti-radio-service.so -i 0
```

It aborts twice during the tested boot and is then restarted successfully by
init.  The decisive tombstone is:

```text
FORTIFY: memcpy: prevented 3735553-byte write into 8444-byte buffer
#05 /odm/lib64/libradioapis.so QmiVsClient::getNecData(...) callback +264
#06 /odm/lib64/libradioapis.so QmiClient::qmiCommandCb(...) +216
#07 /vendor/lib64/libqmi_cci.so qmi_cci_xport_recv +956
```

At `libradioapis.so` text offset `0x571cc`, the callback loads a 32-bit length
from response offset `0x0c` and passes it directly to `__memcpy_chk`, with the
destination capacity fixed at `0x20fc` (8444 bytes).  The received value is
`0x00390001`.  Byte-wise, `01 00 39 00` is consistent with an older response
layout containing separate validity and length fields where the 9R library
expects one aligned 32-bit length.  FORTIFY prevents memory corruption, but
the process is lost.

The live binaries are byte-identical to the local 9R ColorOS 14 donor:

```text
libradioapis.so             14a5a388217a394f2b284713afcde460ab23d6b58e6a3dc5c690f2c7fee0a443
libqti-radio-service.so     6dfdea5b9c0d57bfa45bad0319ab1d8425c642368913ae8bf7a6f62e58646bf7
subsys_daemon               ce4fe98268bcb260c9fd578a4c7182aecab7d8d651fdc1b209c65461bccc2553
```

The factory hotdogg `libradioapis.so` does not export `radioGetNecData` at
all, while the 9R `libqti-radio-service.so` has a hard undefined import for
that symbol.  Replacing only `libradioapis.so` with the factory binary is
therefore not a valid fix.  Replacing the entire factory service island is
also not assumed safe: it uses the older HIDL subsystem interfaces, whereas
the ported service uses the newer NDK interfaces.

## Correct fix direction

The smallest compatibility fix belongs in the ODM radio island, not the
kernel:

1. On hotdogg, report `getNecData` as unsupported without sending the newer
   9R QMI request.  The Android caller already handles a null/error response.
2. Independently harden the 9R callback: reject any returned length greater
   than `0x20fc` before copying and complete the request with an error.  Do not
   clamp and forward a truncated payload because its structure is not valid.
3. Keep the 9R service/library pair together; do not mix the factory
   `libradioapis.so` with the 9R service.
4. Validate after the ODM fix with a cold boot, SIM initialization, repeated
   NEC requests, process lifetime, crash buffer, and modem/data operation.

The early property-read SELinux denial seen for `subsys_daemon` is separate:
the fatal backtrace is a successful QMI receive followed by the unchecked
copy, not a property or SELinux failure.
