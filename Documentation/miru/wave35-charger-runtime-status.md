# Wave 35: charger runtime status ABI

Wave 35 extends the fail-open `oplus_chg/battery` class restored in Waves 33
and 34 with four read-only runtime attributes consumed by the OnePlus 9R
ColorOS 14 charger stack:

- `fast_charge`
- `battery_notify_code`
- `sub_current`
- `charge_timeout`

The implementations use the existing H.40 Oplus charger core state and retain
the authoritative 9R interface semantics. `sub_current` remains zero for the
single-charger configuration and uses the donor-compatible weak backend only
when dual-charger support is active.

This wave does not expose writable charging controls and does not change any
charging, VOOC, timeout, or notification policy.
