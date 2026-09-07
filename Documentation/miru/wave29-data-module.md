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
