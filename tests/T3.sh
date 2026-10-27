#!/bin/sh
# T3 — Phone take-back, watch on the wrist. The phone takes the pod first, then tells the watch
# to stop, checks the pod's total and ends the watch's temp, within about 5 s of the tap.
TEST=T3
. "$(dirname "$0")/lib.sh"
set -u

say "$TEST — phone take-back during a loan"
reset

say "Start on the watch, one loop cycle"
start=$(now)
start_loan "$start"
wait_for watch "$start" 'cycle computed,' 400

say "Take the pod back on the phone"
dismiss_alert
ui phone "tap~" "Sport Mode"
tap=$(now)
ui phone tap "Reclaim Now"
wait_for phone "$tap" 'temp cancelled' 60
wait_for watch "$tap" 'loan closed' 120

say "Checks"
expect_within phone "$tap" 'take-back: pod link up' 5 "phone reached the pod"
expect phone "$tap" 'telling the watch to stop' "phone told the watch to stop"
expect_clean phone "$tap" 'take-back check: delivered' "phone's check of the pod's total"
expect_within phone "$tap" 'temp cancelled' 8 "watch's temp ended"
expect watch "$tap" 'phone took the pod back' "watch stood aside"
expect watch "$tap" 'loan closed' "watch closed the loan"
verdict
