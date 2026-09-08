# Miru H.40 Wave 40: hotdogg SDX55 compatibility

Wave 40 restores the external-modem PCIe/MSI behavior required by OnePlus
project `19861` (hotdogg, OnePlus 7T Pro 5G) without changing the board's
shipping modem reset or firmware interfaces.

## Confirmed failure

The failing boot reaches the SDX55 endpoint at `0001:01:00.0`, then MHI cannot
allocate MSI vectors and returns `-ENOSPC`:

```text
mhi 0001:01:00.0: Failed to enable MSI, ret:-28
mhi: probe of 0001:01:00.0 failed with error -28
```

The later `mhi_arch_esoc_ops_power_on()` NULL-pointer exception is a secondary
failure.  The unsuccessful PCI probe leaves ESOC, PCI event and PM-notifier
callbacks referring to PCI-probe-owned architecture state.

## Donor parity

The H.40 allocator required every multi-vector request to be naturally
aligned.  Both relevant production lines allocate QGIC MSI vectors without
that restriction:

- OnePlus `SM8150_SDX50M_Q_10.0`, which contains the project-19861
  `hotdogg-sdx55m` device trees; and
- OnePlus 9R Android 14 `sm8250_u_14.0.0_op9r`, also using an external SDX55.

Wave 40 therefore uses an alignment mask of zero for the Qualcomm QGIC MSI
controller.  The existing Synopsys-controller behavior is retained.  A
failure-only diagnostic reports the requested, used and total vector counts,
controller type and alignment mask.

## Failure containment

Normal ESOC modem power-off intentionally keeps its callback registrations so
the next power-on can restart MHI.  Wave 40 does not change that path.  It adds
a separate cleanup used only when `mhi_pci_probe()` fails.  That cleanup:

- unregisters the ESOC hook and client;
- unregisters the PM notifier and PCIe event callback;
- releases the bus vote and IPC logging contexts;
- clears the saved architecture pointer; and
- leaves `powered_on` false.

The ESOC power-on entry point also rejects missing controller, PCI-device or
architecture state with `-ENODEV` instead of dereferencing it.

## Intentionally unchanged

- No kernel configuration changes are required.
- No DTB or DTBO property is changed.  The reconstructed project-19861
  PCIe1/MHI/MSI subtree matches the shipping hotdogg DTB.
- The shipping `qcom,ext-sdxprairie` and SDX50-style GPIO reset operations are
  retained.  The OnePlus 9R SPMI reset implementation is not compatible with
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

If allocation still fails, the new single-line MSI diagnostic is the required
evidence for the next correction; it is not a recurring success-path log.
