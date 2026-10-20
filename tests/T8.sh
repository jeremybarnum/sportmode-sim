#!/bin/sh
# T8 — The watch app restarts during a loan. After the relaunch, the watch's first pod report
# checks its insulin before the cycle it feeds decides: nothing doses before it.
TEST=T8
. "$(dirname "$0")/lib.sh"
set -u

say "$TEST — watch app restarts during a loan"
reset

say "Start on the watch, one loop cycle"
start=$(now)
start_loan "$start"
wait_for watch "$start" 'CYCLE VERDICT' 400

say "Force-quit and reopen the watch app"
q=$(now)
sim quit watch
sleep 3
sim launch watch
wait_for watch "$q" 'RESUMED' 60
wait_for watch "$q" '\[odometer\] \(own\)|BOOKED' 400

say "End on the watch"
watch_main
end=$(now)
ui watch tap End
wait_for watch "$end" 'CLOSED — ' 180

say "Checks"
expect watch "$q" 'RESUMED' "watch resumed the loan"
expect_between_none watch "$q" 'RESUMED' '\[odometer\] \(own\)|BOOKED' 'dosemath|enacting' "first pod report before any dose"
expect_clean watch "$q" '\[odometer\] \(own\)' "watch's insulin checks after the restart"
verdict
