#!/bin/sh
# T16 — A granted loan, the watch shut down, the phone near the body. The phone asks the silent
# watch and, with no answer, takes the pod back by itself, counting the watch's insulin.
# (With the phone app in front: a background app is not woken by simulated Bluetooth.)
TEST=T16
. "$(dirname "$0")/lib.sh"
set -u

say "$TEST — watch shut down during a loan"
reset

say "Start on the watch; 0.5 U bolus on the watch"
start=$(now)
start_loan "$start"
b=$(now)
watch_bolus 0.5
wait_for watch "$b" 'ACCEPTED by pod' 120

say "Watch off; nothing touched (up to 15 minutes)"
off=$(now)
sim watch off
wait_for phone "$off" 'asking the watch whether it holds the pod' 900
wait_for phone "$off" 'temp cancelled' 180

say "Watch back on"
on=$(now)
sim watch on
wait_for watch "$on" 'REVOKED|stood aside|CLOSED — ' 300

say "Checks"
expect phone "$off" 'asking the watch whether it holds the pod' "phone asked the silent watch"
expect phone "$off" 'did NOT answer' "no answer: phone takes the pod"
expect phone "$off" 'take-back: pod link up' "phone reached the pod"
expect_residual phone "$off" 'reconcile\[FORCE-RECLAIM\]' 0.3 0.7 "take-back counted the watch's bolus"
expect phone "$off" 'temp cancelled' "watch's temp ended"
expect_between_none watch "$on" 'RESUMED|launch' 'REVOKED|stood aside|CLOSED — ' 'dosemath|enacting' "the watch back on stood aside before any dose"
verdict
