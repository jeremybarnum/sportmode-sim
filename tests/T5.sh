#!/bin/sh
# T5 — Phone take-back with the pod out of reach: refused with a message, nothing changes; with
# the pod back, the take-back goes through as T3.
TEST=T5
. "$(dirname "$0")/lib.sh"
set -u

say "$TEST — take-back with the pod out of reach"
reset

say "Start on the watch"
start=$(now)
start_loan "$start"

say "Pod out of reach; take back on the phone"
sim pod away
t1=$(now)
take_back
wait_for phone "$t1" 'take-back REFUSED' 30
sleep 3
dismiss_alert

say "Pod back; take back again"
sim pod back
sleep 5
t2=$(now)
take_back
wait_for phone "$t2" 'temp cancelled' 60
wait_for watch "$t2" 'CLOSED — ' 120

say "Checks"
expect_within phone "$t1" 'take-back REFUSED' 8 "refused while the pod is away"
expect phone "$t1" 'take-back REFUSED.*loan unchanged.*nothing sent to the watch' "loan unchanged, nothing sent to the watch"
expect_within phone "$t2" 'take-back: pod link up' 5 "second take-back reached the pod"
expect_clean phone "$t2" 'reconcile\[FORCE-RECLAIM\]' "phone's check of the pod's total"
expect watch "$t2" 'REVOKED' "watch stood aside"
verdict
