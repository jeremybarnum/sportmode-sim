#!/bin/sh
# T22 — Start, End and Take Back during a bolus. Nobody takes the pod while it is giving a bolus:
# each is refused with the seconds left, and goes through once the bolus has finished. (b2): an End
# moments after a watch bolus is sent, before the pod accepts it, is refused too. A 2 U bolus takes
# the simulated pod about 80 s (0.05 U every 2 s), as a DASH pod; for (b2) the pod is made to hold
# the bolus command 6 s before accepting it, as a real pod takes seconds.
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

say "a new loan; (b2) End within seconds of sending a watch bolus, before the pod accepts it"
c0=$(now)
start_loan "$c0"
# A real pod takes seconds to accept a bolus; the simulated one answers at once unless held.
sim pod slow 6
b3=$(now)
watch_bolus_send 2
watch_main
te=$(now)
ui watch tap End
sleep 8
say "wait for the bolus to be accepted and given"
wait_for watch "$b3" 'ACCEPTED by pod' 60 >/dev/null
sleep 85

say "(c) in the same loan: 2 U bolus on the watch; Take Back on the phone while it is being given"
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
acc=$(lines watch "$b3" 'ACCEPTED by pod' | head -1 | cut -c1-8)
if [ -n "$acc" ] && [ "$te" \< "$acc" ]; then pass "(b2) the End came before the pod accepted the bolus (End $te, accepted $acc)" ""
else fail "(b2) the End came before the pod accepted the bolus (End $te, accepted ${acc:-never})" ""; fi
expect watch "$te" 'HAND-BACK refused' "(b2) End refused while the bolus was sent but not yet accepted"
expect_none_between watch "$te" "$c" 'HAND-BACK requested' "(b2) no hand-back started"
expect_none_between phone "$te" "$c" 'offer RX' "(b2) no hand-back offer reached the phone"
expect phone "$tb" 'take-back REFUSED — the pod is giving the watch.s bolus' "(c) Take Back refused while the watch's bolus is being given"
expect_none_between watch "$tb" "$tb2" 'REVOKED' "(c) the loan continued during the bolus (no REVOKED)"
expect watch "$tb2" 'REVOKED' "(c) the Take Back after the bolus took the pod"
verdict
