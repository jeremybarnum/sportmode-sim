#!/bin/sh
# T7 — Offline start, watch bolus, phone back before it hears from the watch. If the phone reads
# the pod first it books the watch's insulin, and the watch's records retire it at the hand-back;
# if it hears from the watch first it stands aside and books nothing. Either way the final check
# is clean.
TEST=T7
. "$(dirname "$0")/lib.sh"
set -u

say "$TEST — offline start, watch bolus, phone back"
reset

say "Phone out of reach; offline start; 0.5 U bolus on the watch"
sim phone away
start=$(now)
offline_start "$start"
watch_bolus 0.5

say "Three minutes; then the phone comes back and reads"
sleep 180
sim phone back
back=$(now)
wait_reading "$back" 400
sleep 30

say "End on the watch"
watch_main
end=$(now)
ui watch tap End
wait_for watch "$end" 'CLOSED — ' 180
wait_for phone "$end" 'temp cancelled' 120

say "Checks"
if [ -n "$(lines phone "$back" 'estimate BOOKED')" ]; then
	expect_count phone "$back" 'estimate BOOKED' 1 "phone booked the watch's insulin once"
	expect phone "$back" 'estimate RETIRED' "the watch's records retired it"
else
	pass "phone heard from the watch first and booked nothing" "no estimate BOOKED since $back"
fi
expect phone "$back" 'RETRO-ACK' "phone adopted the loan"
expect_clean phone "$end" 'reconcile\[AUTHORITATIVE\]' "final check"
expect_none phone "$back" 'Overstated' "no Insulin On Board May Be Overstated"
verdict
