#!/bin/sh
# T22 — Start, End and Take Back during a bolus. Nobody takes the pod while it is giving a bolus:
# each is refused with the seconds left, and goes through once the bolus has finished. (b2): an End
# moments after a watch bolus is sent, before the pod accepts it, is refused too. A 2 U bolus takes
# the simulated pod about 80 s (0.05 U every 2 s), as a DASH pod; for (b2) the pod is made to hold
# the bolus command 3 s before accepting it (under the 5 s the watch waits for a reply). (b3): a watch
# bolus asked for while an End's hand-back waits for the phone's answer (the link made 3 s slow each
# way) is refused, "Bolus Not Sent", and the End completes (ruled 2026-10-21).
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
sim pod slow 3
b3=$(now)
watch_bolus_send 2
watch_main
te=$(now)
ui watch tap End
sleep 8
say "wait for the bolus to be accepted and given"
wait_for watch "$b3" 'MANUAL BOLUS .*ACCEPTED by pod' 60 >/dev/null
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

say "a new loan; (b3) End, then a watch bolus asked for while the hand-back waits for the phone's answer"
# Each live message arrives 3 s late, so the phone's acknowledgement reaches the watch about 7 s
# after the End: the bolus is asked for in between, and the watch must refuse it.
d0=$(now)
start_loan "$d0"
not_sent=$(python3 "$root/tests/notifications.py" "$WATCH_SIM_ID" delivered | grep -c "Bolus Not Sent")
sim link slow 3
watch_main
td=$(now)
ui watch tap End
# The bolus taps as fast as they go; the refusal may come at any step, so none of them ends the test.
watch_page 1
for step in "tap $WATCH_BOLUS" "tap +" "tap +" "tap +" "tap +" "tap Bolus" "double Turn Digital"; do
	"$UI" watch $step >/dev/null 2>&1 || true
done
sleep 20
sim link normal
wait_for watch "$td" 'CLOSED — ' 120
wait_for phone "$td" 'reclaim VERIFIED' 120
watch_close_sheets
not_sent2=$(python3 "$root/tests/notifications.py" "$WATCH_SIM_ID" delivered | grep -c "Bolus Not Sent")

say "Checks"
expect phone "$a" 'grant REFUSED — this phone.s bolus is still being given' "(a) Start refused while the phone's bolus is being given"
expect_none_between phone "$a" "$a2" 'GRANT — releasing pod' "(a) nothing released by the refused Start"
expect watch "$a2" 'ACTIVE — epoch' "(a) the Start after the bolus went through"
expect watch "$b" 'HAND-BACK refused( at the tap)? — a bolus is being given' "(b) End refused while the watch's bolus is being given"
expect_none_between phone "$b" "$b2" 'offer RX' "(b) no hand-back offer reached the phone during the bolus"
expect watch "$b2" 'CLOSED — ' "(b) the End after the bolus handed back"
acc=$(lines watch "$b3" 'MANUAL BOLUS .*ACCEPTED by pod' | head -1 | cut -c1-8)
if [ -n "$acc" ] && [ "$te" \< "$acc" ]; then pass "(b2) the End came before the pod accepted the bolus (End $te, accepted $acc)" ""
else fail "(b2) the End came before the pod accepted the bolus (End $te, accepted ${acc:-never})" ""; fi
expect watch "$te" 'HAND-BACK refused at the tap — a bolus is being given \(ends when the pod has it\)' "(b2) End refused while the bolus was sent but not yet accepted"
expect_none_between watch "$te" "$c" 'HAND-BACK requested' "(b2) no hand-back started"
expect_none_between phone "$te" "$c" 'offer RX' "(b2) no hand-back offer reached the phone"
expect phone "$tb" 'take-back REFUSED — the pod is giving the watch.s bolus' "(c) Take Back refused while the watch's bolus is being given"
expect_none_between watch "$tb" "$tb2" 'REVOKED' "(c) the loan continued during the bolus (no REVOKED)"
expect watch "$tb2" 'REVOKED' "(c) the Take Back after the bolus took the pod"
expect watch "$td" 'BOLUS REFUSED — .*an End is waiting' "(b3) the bolus asked for while the End waited was refused"
expect_none watch "$td" 'MANUAL BOLUS .*enacting' "(b3) no bolus sent to the pod"
[ "$not_sent2" -gt "$not_sent" ] && pass "(b3) the watch said \"Bolus Not Sent\"" "" || fail "(b3) the watch said \"Bolus Not Sent\"" "no new such notification"
expect watch "$td" 'drain complete' "(b3) the End went on: the drain completed"
expect watch "$td" 'CLOSED — ' "(b3) the End completed"
expect phone "$td" 'reclaim VERIFIED' "(b3) the phone took the pod back"
expect_clean phone "$td" 'reconcile\[AUTHORITATIVE\]' "(b3) the phone's audit"
verdict
