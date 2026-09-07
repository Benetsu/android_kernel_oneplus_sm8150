# Wave 36: charger safety diagnostics ABI

Wave 36 restores seven read-only OnePlus 9R ColorOS 14 charger attributes that
map directly to state and callbacks already present in the H.40 charger core:

- `design_capacity`
- `battery_charging_state`
- `charge_term_current`
- `input_current_settled`
- `short_c_hw_status`
- `short_ic_otp_status`
- `short_ic_otp_value`

The short-circuit and userspace diagnostic attributes retain their existing
H.40 configuration guards. No writable charger controls are added, and reads
do not initiate a hardware test or alter charge policy.
