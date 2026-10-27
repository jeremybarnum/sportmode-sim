#!/bin/sh
# T18 — End on the watch with the phone away. The End waits 10 s for the phone's answer, then is
# refused on screen; the loan continues. With the phone back, End hands back cleanly.
TEST=T18
. "$(dirname "$0")/lib.sh"
set -u

say "$TEST — End with the phone away"
reset

say "Start on the watch"
start=$(now)
start_loan "$start"
# The phone must have heard the watch take over: away before that, it ends a loan it never saw start.
wait_for phone "$start" 'until the watch took over' 30

say "Phone out of reach; End on the watch"
sim phone away
watch_main
e=$(now)
ui watch tap End
wait_for watch "$e" 'not possible' 30
sleep 5
still=0; shows watch End && still=1

say "Phone back; End again"
sim phone back
sleep 15
watch_main
e2=$(now)
ui watch tap End
wait_for watch "$e2" 'loan closed' 180
wait_for phone "$e2" 'temp cancelled' 120

say "Checks"
expect_within watch "$e" 'hand-back not possible' 13 "End refused after the 10 s wait"
if [ "$still" = 1 ]; then pass "loan continued (End still on screen)" ""; else fail "loan continued (End still on screen)" ""; fi
expect_clean phone "$e2" 'hand-back check:' "the second End's check"
verdict
