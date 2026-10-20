#!/bin/sh
# T1 — Ordinary loan, ended on the watch. The watch takes the pod, loops, hands it back; the
# phone's check over the watch's window is clean and the watch's temp is ended.
TEST=T1
. "$(dirname "$0")/lib.sh"
set -u

say "$TEST — ordinary loan, ended on the watch"
drivers
watch_main
"$UI" watch wait 5 "Start Sport Mode" >/dev/null || abort "the watch shows no Start: is a loan running?"

say "Start on the watch"
start=$(now)
ui watch tap "Start Sport Mode"
wait_for watch "$start" 'ACTIVE — epoch' 90
active=$(now)

say "Loan active; two watch loop cycles (up to 12 minutes, paced by sensor readings)"
wait_for watch "$active" 'CYCLE VERDICT' 720 2

say "End on the watch"
end=$(now)
ui watch tap End
wait_for watch "$end" 'CLOSED — ' 120
wait_for phone "$end" 'temp cancelled' 60

say "Checks"
expect phone "$start" 'until the watch took over' "phone closed its own window at the takeover"
expect watch "$start" 'ACTIVE — epoch' "watch active"
expect_clean watch "$start" '\[odometer\] \(own\)' "watch insulin checks at each reading"
expect watch "$end" 'HAND-BACK requested' "hand-back started"
expect watch "$end" 'ack RECEIVED' "phone acknowledged the hand-back"
expect_clean phone "$end" 'reconcile\[AUTHORITATIVE\]' "phone's check over the watch's window"
expect phone "$end" 'temp cancelled' "watch's temp ended"
expect_none watch "$start" 'BOOKED' "nothing booked during an ordinary loan"
expect_none phone "$start" 'Unexplained Insulin' "no Unexplained Insulin notice"
verdict
