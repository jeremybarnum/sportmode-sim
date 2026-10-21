#!/bin/sh
# P14 — A bolus during a loan. (a) End during a watch bolus is refused and goes through after it.
# (b) Take Back during a watch bolus goes through: this line does not refuse it.
TEST=P14
. "$(dirname "$0")/lib.sh"
set -u

say "$TEST — a bolus during a loan"
reset

say "(a) Start; a 2 U watch bolus; End while it is being given"
a=$(now)
start_loan "$a"
watch_bolus_start 2 >/dev/null
watch_main
te=$(now)
ui watch tap End
sleep 5
watch_close_sheets
say "wait for the bolus to finish (about 80 s), then End again"
sleep 90
watch_main
te2=$(now)
ui watch tap End
wait_for watch "$te2" 'CLOSED — ' 120

say "(b) A new loan; a 2 U watch bolus; Take Back while it is being given"
reset
b=$(now)
start_loan "$b"
watch_bolus_start 2 >/dev/null
tb=$(now)
take_back
wait_for watch "$tb" 'REVOKED' 60
wait_for phone "$tb" 'R37 audit|reclaim VERIFIED' 360

say "Checks"
expect watch "$te" 'End REFUSED — the watch.s bolus is still being delivered' "(a) End refused during the bolus"
expect_none_between watch "$te" "$te2" 'HAND-BACK requested' "(a) no hand-back started during the bolus"
expect watch "$te2" 'CLOSED — ' "(a) End after the bolus handed back"
expect phone "$tb" 'reclaim ladder' "(b) Take Back during the bolus went ahead"
expect watch "$tb" 'REVOKED' "(b) the watch let the pod go"
verdict
