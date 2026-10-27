#!/bin/sh
# T4 — Phone take-back with the watch's records missing. The insulin the phone has no record of
# is booked once as an estimate; the phone's next reading does not count it again; the watch's
# records, when they come home, retire the estimate.
TEST=T4
. "$(dirname "$0")/lib.sh"
set -u

say "$TEST — take-back with the watch's records missing"
reset

say "Start on the watch, one loop cycle"
start=$(now)
start_loan "$start"
wait_for watch "$start" 'cycle computed,' 400
# The phone must have heard the watch take over: away before that, it ends a loan it never saw start.
wait_for phone "$start" 'until the watch took over' 30

say "Phone out of reach; 0.5 U bolus on the watch"
sim phone away
watch_bolus 0.5

say "Watch off; phone back; the phone takes the pod back"
sim watch off
sim phone back
sleep 5
tb=$(now)
take_back
wait_for phone "$tb" 'take-back check: delivered' 60
wait_for phone "$tb" 'estimate booked' 60

say "The phone's next reading"
r=$(now)
wait_reading "$r" 400
wait_for phone "$r" 'this phone.s insulin check' 300

say "Watch back on: its records come home"
on=$(now)
sim watch on
wait_for watch "$on" 'resumed loan' 120
wait_for phone "$on" 'estimate retired' 400

say "Checks"
expect_residual phone "$tb" 'take-back check: delivered' 0.3 0.7 "take-back's check finds the watch's bolus"
expect_count phone "$tb" 'estimate booked' 1 "the missing insulin booked once"
expect_clean phone "$r" 'this phone.s insulin check' "the next reading does not count it again"
expect watch "$on" 'resumed loan' "watch resumed"
expect_between_none watch "$on" 'resumed loan' 'phone took the pod back|stood aside' 'dosemath|enacting' "watch stood aside before any dose"
expect phone "$on" 'estimate retired' "the watch's records retired the estimate"
expect_none phone "$tb" 'Overstated' "no Insulin On Board May Be Overstated"
verdict
