#!/bin/sh
# T9 — The watch off longer than 6 hours during a loan. It does not resume: its records go home,
# "Sport Mode Ended", the pod let go. The 6 hours are simulated by aging the watch's saved last
# pod reading while it is off.
TEST=T9
. "$(dirname "$0")/lib.sh"
set -u

say "$TEST — watch off longer than 6 hours"
reset

say "Start on the watch, one loop cycle"
start=$(now)
start_loan "$start"
wait_for watch "$start" 'CYCLE VERDICT' 400
state=$(watch_state_file) || abort "no watch state file"

say "Watch off; the phone takes the pod back; seven hours pass for the watch"
sim watch off
sleep 3
tb=$(now)
take_back
wait_for phone "$tb" 'take-back: pod link up' 60
age_watch_ledger "$state" 7

say "Watch back on"
on=$(now)
sim watch on
wait_for watch "$on" 'RESUME declined' 120
sleep 30

say "Checks"
expect watch "$on" 'RESUME declined' "watch did not resume a loan older than insulin's action"
expect_none watch "$on" 'dosemath|enacting' "watch did not dose"
expect_none phone "$on" 'estimate BOOKED' "phone booked nothing for the records"
verdict
