#!/bin/sh
# T3 — Phone take-back, watch on the wrist. The phone takes the pod first, then tells the watch
# to stop, checks the pod's total and ends the watch's temp, within about 5 s of the tap.
TEST=T3
. "$(dirname "$0")/lib.sh"
set -u

say "$TEST — phone take-back during a loan"
drivers
watch_main
"$UI" watch wait 5 "Start Sport Mode" >/dev/null || abort "the watch shows no Start: is a loan running?"

say "Start on the watch"
start=$(now)
ui watch tap "Start Sport Mode"
wait_for watch "$start" 'ACTIVE — epoch' 90
active=$(now)

say "Loan active; one watch loop cycle (up to 6 minutes)"
wait_for watch "$active" 'CYCLE VERDICT' 400

say "Take the pod back on the phone"
ui phone tap "Sport Mode Active"
tap=$(now)
ui phone tap "Reclaim Now"
wait_for phone "$tap" 'temp cancelled' 60
wait_for watch "$tap" 'CLOSED — ' 120

say "Checks"
expect_within phone "$tap" 'take-back: pod link up' 5 "phone reached the pod"
expect phone "$tap" 'send revoke|watch told to stop' "phone told the watch to stop"
expect_clean phone "$tap" 'reconcile\[FORCE-RECLAIM\]' "phone's check of the pod's total"
expect_within phone "$tap" 'temp cancelled' 8 "watch's temp ended"
expect watch "$tap" 'REVOKED' "watch stood aside"
expect watch "$tap" 'CLOSED — ' "watch closed the loan"
verdict
