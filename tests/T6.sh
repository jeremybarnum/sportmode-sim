#!/bin/sh
# T6 — Offline start with the watch alive, then back to the phone. The phone adopts a loan it
# never granted; its own window ends at the watch's takeover; the hand-back's check is clean.
TEST=T6
. "$(dirname "$0")/lib.sh"
set -u

say "$TEST — offline start, back to the phone"
reset

say "Phone out of reach; offline start on the watch"
sim phone away
start=$(now)
offline_start "$start"

say "Two watch loop cycles"
wait_for watch "$start" 'CYCLE VERDICT computed=ok' 720 2

say "Phone back; End on the watch"
sim phone back
sleep 10
watch_main
end=$(now)
ui watch tap End
wait_for watch "$end" 'CLOSED — ' 180
wait_for phone "$end" 'temp cancelled' 120

say "Checks"
expect watch "$start" 'SEIZE confirmed' "offline start confirmed"
expect watch "$start" 'seized loan ACTIVE' "watch active on its own"
expect phone "$start" 'RETRO-ACK' "phone adopted the loan"
expect phone "$start" 'until the watch took over' "phone's own window ended at the watch's takeover"
expect_clean phone "$end" 'reconcile\[AUTHORITATIVE\]' "hand-back's check"
expect phone "$end" 'temp cancelled' "watch's temp ended"
verdict
