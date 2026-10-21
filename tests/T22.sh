#!/bin/sh
# T22 — Start, End and Take Back during a bolus. Nobody takes the pod while it is giving a bolus:
# each is refused with the seconds left, and goes through once the bolus has finished. A 2 U bolus
# takes the simulated pod about 80 s (0.05 U every 2 s), as a DASH pod.
TEST=T22
. "$(dirname "$0")/lib.sh"
set -u

say "$TEST — Start, End and Take Back during a bolus"
reset

say "(a) 2 U bolus on the phone; Start on the watch while it is being given"
pb=$(now)
phone_bolus 2
sleep 8
a=$(tap_start)
sleep 12
say "wait for the phone's bolus to finish, then Start again"
sleep 75
a2=$(now)
start_loan "$a2"

say "(b) in the loan: 2 U bolus on the watch; End while it is being given"
b=$(watch_bolus_start 2)
sleep 5
watch_main
ui watch tap End
sleep 12
say "wait for the watch's bolus to finish, then End again"
sleep 75
b2=$(now)
watch_main
ui watch tap End
wait_for watch "$b2" 'CLOSED — ' 180
wait_for phone "$b2" 'temp cancelled' 60
sleep 5

say "a new loan; (c) 2 U bolus on the watch; Take Back on the phone while it is being given"
c0=$(now)
start_loan "$c0"
c=$(watch_bolus_start 2)
sleep 5
tb=$(now)
take_back
sleep 12
dismiss_alert
say "wait for the watch's bolus to finish, then Take Back again"
sleep 75
tb2=$(now)
take_back
wait_for watch "$tb2" 'CLOSED — ' 120

say "Checks"
expect phone "$a" 'grant REFUSED — this phone.s bolus is still being given' "(a) Start refused while the phone's bolus is being given"
expect_none_between phone "$a" "$a2" 'GRANT — releasing pod' "(a) nothing released by the refused Start"
expect watch "$a2" 'ACTIVE — epoch' "(a) the Start after the bolus went through"
expect watch "$b" 'HAND-BACK refused — a bolus is being given' "(b) End refused while the watch's bolus is being given"
expect_none_between phone "$b" "$b2" 'offer RX' "(b) no hand-back offer reached the phone during the bolus"
expect watch "$b2" 'CLOSED — ' "(b) the End after the bolus handed back"
expect phone "$tb" 'take-back REFUSED — the pod is giving the watch.s bolus' "(c) Take Back refused while the watch's bolus is being given"
expect_none_between watch "$tb" "$tb2" 'REVOKED' "(c) the loan continued during the bolus (no REVOKED)"
expect watch "$tb2" 'REVOKED' "(c) the Take Back after the bolus took the pod"
verdict
