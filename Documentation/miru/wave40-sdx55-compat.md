# Miru H.40 Wave 40.1: hotdogg SDX55 compatibility

Wave 40.1 corrects the external-modem PCIe/MSI experiment for OnePlus project
`19861` (hotdogg, OnePlus 7T Pro 5G) without changing the board's shipping
modem reset, firmware, DTB or DTBO interfaces.

## Confirmed failure

The failing boot reaches the SDX55 endpoint at `0001:01:00.0`, then MHI cannot
allocate MSI vectors and returns `-ENOSPC`:

```text
mhi 0001:01:00.0: Failed to enable MSI, ret:-28
mhi: probe of 0001:01:00.0 failed with error -28
```

The later ColorOS `BOOT_FAIL_ACTION_PANIC`, after the expected MHI pipe never
appears, is a consequence rather than the first failure. A historical null
pointer in `mhi_arch_esoc_ops_power_on()` is separately contained by retaining
Wave 40's defensive controller/device/state guard.

## Controlled comparison

The first Miru test retained the complete working hotdogg modem/DSP firmware,
vendor, ODM, DTB and DTBO. Replacing only its factory kernel introduced the
failure, which isolates the remaining incompatibility to kernel behavior.

Direct comparison with the shipping hotdogg 4.14.180 kernel establishes that
its Qualcomm QGIC allocator uses the original natural alignment mask
`nr_irqs - 1`. This alignment is also required by PCI multi-message MSI: the
device derives individual message data values from a naturally aligned base.
Wave 40's unaligned QGIC allocation is therefore reverted.

The hotdogg MHI device tree describes 15 event rings, so MHI requests 16 MSI
vectors. PCIe1 exposes a 32-vector QGIC pool. A clean, aligned 16-vector request
fits that pool; the remaining question is where the observed `-28` originates.

## Stock retry semantics

Normal ESOC modem power-off intentionally keeps its callback registrations so
the next power-on can restart MHI. The shipping kernel also preserves these
registrations after the initial PCI probe fails. Wave 40's new teardown removed
that ColorOS retry path, so Wave 40.1 removes the teardown and restores the
shipping probe/error flow. The defensive ESOC null guard remains.

## Failure provenance

Wave 40.1 adds no recurring success-path logging. If MSI setup fails, three
failure-only messages distinguish the branches:

- the MHI line reports requested vectors, endpoint-advertised capacity and
  the full PCI address;
- the generic MSI-domain line reports the original error that Linux otherwise
  replaces with `-ENOSPC`; and
- the QGIC line reports bitmap usage, pool size and alignment when no suitable
  range exists.

Interpretation is direct: endpoint capacity below 16 identifies PCI
capability/config-space handling; an MSI-domain line without a QGIC no-space
line identifies IRQ descriptor allocation; and all three lines identify QGIC
bitmap state or fragmentation.

## Intentionally unchanged

- No kernel configuration changes are required.
- No DTB or DTBO property is changed. The reconstructed project-19861
  PCIe1/MHI/MSI subtree matches the shipping hotdogg DTB.
- The shipping `qcom,ext-sdxprairie` and SDX50-style GPIO reset operations are
  retained. The OnePlus 9R SPMI reset implementation is not compatible with
  hotdogg's board wiring.
- No modem, WLAN, vendor, ODM or DLKM firmware is changed.
- No exported symbol or external-module ABI is changed.

## Phone validation

The wave is successful when a matching kernel and DLKM package shows all of
the following:

- no `Failed to enable MSI, ret:-28` message;
- the `17cb:0306` endpoint receives 16 MSI vectors and enters MHI mission mode;
- no exception in `mhi_arch_esoc_ops_power_on()` and no forced external-modem
  boot-failure panic;
- cellular registration and mobile data operate; and
- `wlan0` appears and connects, confirming the ICNSS/ESOC dependency also
  recovered.

This wave deliberately does not claim the modem is fixed before a phone test.
If allocation still fails, the failure-only provenance above is the required
evidence for the next correction.
