#!/bin/sh
# T1 — Ordinary loan, ended on the watch. The watch takes the pod, loops, hands it back; the
# phone's check over the watch's window is clean and the watch's temp is ended.
TEST=T1
. "$(dirname "$0")/lib.sh"
set -u

say "$TEST — ordinary loan, ended on the watch"
reset

say "Start on the watch"
start=$(now)
start_loan "$start"

say "Two watch loop cycles (up to 12 minutes, paced by sensor readings)"
wait_for watch "$start" 'cycle computed,' 720 2

say "End on the watch"
watch_main
end=$(now)
ui watch tap End
wait_for watch "$end" 'loan closed' 120
wait_for phone "$end" 'temp cancelled' 60

say "Checks"
expect phone "$start" 'until the watch took over' "phone closed its own window at the takeover"
expect watch "$start" 'loan [0-9]+ active' "watch active"
expect_clean watch "$start" 'insulin check over' "watch insulin checks at each reading"
expect watch "$end" 'hand-back requested' "hand-back started"
expect watch "$end" 'phone acknowledged the hand-back' "phone acknowledged the hand-back"
expect_clean phone "$end" 'hand-back check:' "phone's check over the watch's window"
expect phone "$end" 'temp cancelled' "watch's temp ended"
expect_none watch "$start" 'booked [0-9.]+ U' "nothing booked during an ordinary loan"
expect_none phone "$start" 'Unexplained Insulin' "no Unexplained Insulin notice"
verdict
