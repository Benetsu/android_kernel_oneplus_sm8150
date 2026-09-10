# Wave 41: OnePlus 9R HANS and cgroup v2 freezer parity

Wave 41 is based on the proven Wave 40.2 hotdogg-compatible source.  The
authoritative behavior comes from the OnePlus 9R Android 14 SM8250 kernel at
commit `b339700f85cb393563c802733bc39cca2617190c`.

The wave completes these connected pieces as one freezer/HANS ABI unit:

1. Preserve the H.40 cgroup v1 freezer as `legacy_freezer.c`.
2. Build the donor cgroup v2 freezer core independently of the v1 controller.
3. Publish `cgroup.freeze` on non-root cgroup v2 directories.
4. Publish the effective `frozen` state through `cgroup.events`.
5. Propagate requested and effective freeze state through cgroup descendants.
6. Track frozen tasks and descendants during task migration and cgroup removal.
7. Integrate freezer traps with signal delivery, ptrace stops, group stops and
   vfork waits.
8. Inherit freezer state across fork and arm new children before userspace runs.
9. Balance freezer accounting when a task exits or leaves a frozen cgroup.
10. Report the 9R `HANS_USE_CGRPV2` capability after the netlink loopback
    handshake and on the explicit compatibility query.
11. Make HANS frozen-task detection understand both the new cgroup v2 state and
    the retained legacy freezer state.
12. Record the new userspace-visible controls and netlink contract in the ABI
    ledger.

The existing `CONFIG_CGROUP_FREEZER=y` remains enabled for legacy policy.
`CONFIG_OPLUS_HANS=y` is explicit in the reproduced H.40 configuration.  No
vendor, ODM, device-tree, modem or charger behavior is changed by this wave.

Expected runtime evidence after deployment:

```text
/sys/fs/cgroup/<group>/cgroup.freeze
/sys/fs/cgroup/<group>/cgroup.events  # includes: frozen 0|1
```

Writing `1` to a test cgroup's `cgroup.freeze` must eventually change its
`cgroup.events` line to `frozen 1`; writing `0` must restore `frozen 0` and let
the contained tasks run.  The HANS daemon should receive code `-99` after its
loopback handshake instead of falling back to the older freezer contract.
