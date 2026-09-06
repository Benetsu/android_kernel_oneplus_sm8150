# Wave 29: Android 14 game/network data module

After Wave 28 ordered UX scheduling passed its complete build and artifact
gate, Wave 29 ports `CONFIG_OPLUS_FEATURE_DATA_MODULE` from the authoritative
OnePlus 9R Android 14 external source. Both donor Kona production
configurations enable the feature.

The bounded built-in module restores the `comm_netlink` version-1 generic
netlink family and its complete protobuf command set. Its data plane includes:

- IPv4 and IPv6 per-UID DPI and stream-speed accounting;
- application, function, and stream classification;
- Tencent `tmgp_sgame` server discovery and bidirectional delay statistics;
- log-stream and HeyTap-market flow classification;
- traffic-control classifier integration;
- the `/proc/sys/net/oplus_dpi/*` and `/proc/sys/net/tmgp_sgame/*` control and
  counter families.

The exact donor directory is connected through the existing
`net/oplus_modules` source link. It requires no new main-kernel hook and adds no
DLKM to the 32-module payload. Debug logging defaults off, and detailed game
packet accounting remains driven by userspace UID/server selection.

The Miru 4.14 compatibility layer removes one unused newer-kernel CRC header,
uses the equivalent 4.14 raw-monotonic clock API, and maps the donor DPI
traffic-control classifier onto the 4.14 RCU/work, IDR, callback, and extension
validation interfaces without changing its packet-classification ABI.

Wave 29 run `34062386716` passed kernel plus reconstructed H.40 DTB/DTBO
compilation, the matching 32 external modules, packaging, and artifact upload
at kernel commit `480e724a2d9ee3be1ebe9995bf23b86a9f705a5a` and external
commit `3fe5933901e630913913ffa8614b59502a13a51f`. Artifact
`miru-h40-wave29-data-module-kernel-and-modules` (`9998269322`) is 566184063
bytes and has GitHub digest
`sha256:473fa05b98dab96af3e823ac4988d1db84130063cf17b8b7716e75ba736d14f1`.
