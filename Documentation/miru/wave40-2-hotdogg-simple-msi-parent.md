# Wave 40.2: hotdogg simple MSI-parent compatibility

## Scope

Wave 40.2 fixes PCI MSI-domain discovery for the external SDX55 modem on
OnePlus 7T Pro 5G (`hotdogg`, project 19861). It is based on Wave 40.1 and
does not alter the firmware-derived H.40 device trees, QGIC vector allocator,
MHI channel layout, or subsystem restart policy.

## Live failure evidence

Two rooted Wave 40.1 boots reproduced the same sequence:

```text
OF: /soc/qcom,pcie@1c08000: could not get #msi-cells for /soc/qcom,pcie1_msi@17a00040
pci 0001:01:00.0: [17cb:0306] type 00 class 0xff0000
iommu: Adding device 0001:01:00.0 to group 54
[E][mhi_init_pci_dev] Failed to enable MSI, ret:-28 requested:16 capable:32 bdf:0001:01:00.0
mhi: probe of 0001:01:00.0 failed with error -28
```

The Wave 40.1 failure-only diagnostics did not report either an IRQ-domain
allocation failure or QGIC bitmap exhaustion. The PCI function advertises 32
MSI vectors and MHI requests 16. The failure therefore happens because the PCI
device never inherits the already-created Qualcomm MSI domain.

## Root cause

The shipped hotdogg DTB uses the Qualcomm simple `msi-parent` representation:

```dts
qcom,pcie@1c08000 {
	msi-parent = <&pcie1_msi>;
};

pcie1_msi: qcom,pcie1_msi@17a00040 {
	compatible = "qcom,pci-msi";
	msi-controller;
	/* no #msi-cells: this is the simple form */
};
```

Miru's old `of_msi_get_domain()` unconditionally parses `msi-parent` as the
complex form and consequently rejects this factory DT. PCI then falls back to
the generic architecture MSI path; that path cannot satisfy a 16-vector MSI
request and `pci_alloc_irq_vectors()` returns `-ENOSPC`.

## Fix

Backport the Android 14 OnePlus 9R donor implementation of
`of_msi_get_domain()`:

- resolve a simple single-phandle `msi-parent` directly when its controller
  intentionally has no `#msi-cells` property;
- retain complex `msi-parent` parsing for platform-MSI consumers.

This matches the authoritative 9R kernel behavior and preserves the exact
factory hotdogg DT representation rather than inventing a cell argument that
the firmware never supplied.

## Expected validation

A successful boot must show all of the following:

- no `could not get #msi-cells` message for PCIe1;
- no `Failed to enable MSI, ret:-28` message;
- MHI creates `/dev/mhi_0306_01.01.00_pipe_2`;
- the external modem reaches MHI ready/power-on states;
- no ColorOS modem boot-failure panic;
- cellular radio and data enumerate normally.
