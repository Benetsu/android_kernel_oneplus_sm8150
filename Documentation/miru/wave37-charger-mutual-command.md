# Wave 37: charger mutual command mailbox

Wave 37 restores the 9R ColorOS 14 path
`/sys/class/oplus_chg/common/mutual_cmd` and its 264-byte command/reply wire
format.

The 9R endpoint blocks a charger-HAL reader until an in-kernel producer queues
a command. The only producer present in the authoritative 9R charger sources
is wireless third-party authentication. Hotdogg has no wireless charging, so
the H.40 compatibility endpoint intentionally remains idle while allowing the
charger HAL to open its expected path without repeated missing-node errors.

This wave does not import the 9R common charging-policy engine and does not
change wired charging, VOOC, current limits, battery state, or thermal policy.
