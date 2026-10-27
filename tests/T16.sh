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
watch_bolus 0.5

say "Watch off; nothing touched (up to 15 minutes)"
off=$(now)
sim watch off
wait_for phone "$off" 'asking the watch whether it holds the pod' 900
wait_for phone "$off" 'temp cancelled' 180

say "Watch back on"
on=$(now)
sim watch on
wait_for watch "$on" 'phone took the pod back|stood aside|loan closed' 300

say "Checks"
expect phone "$off" 'asking the watch whether it holds the pod' "phone asked the silent watch"
expect phone "$off" 'taking the pod back: no answer' "no answer: phone takes the pod"
expect phone "$off" 'take-back: pod link up' "phone reached the pod"
# The watch's records may reach the phone before the watch goes off (then the take-back expects the
# bolus and the residual is near zero) or not (then the residual books it): either way, delivered.
l=$(lines phone "$off" 'take-back check: delivered' | tail -1)
verdict_ok=$(echo "$l" | awk '{ d = 0; r = 9
	if (match($0, /delivered[ =][0-9.]+/)) d = substr($0, RSTART + 10, RLENGTH - 10) + 0
	if (match($0, /residual[ =][+-]?[0-9.]+/)) r = substr($0, RSTART + 9, RLENGTH - 9) + 0
	if (d >= 0.45 && ((r >= -0.2 && r <= 0.2) || (r >= 0.3 && r <= 0.7))) print "yes" }')
if [ "$verdict_ok" = yes ]; then pass "take-back accounted for the watch's bolus" "$l"
else fail "take-back accounted for the watch's bolus" "${l:-no take-back check line}"; fi
expect phone "$off" 'temp cancelled' "watch's temp ended"
expect_between_none watch "$on" 'resumed loan|app launched' 'phone took the pod back|stood aside|loan closed' 'dosemath|enacting' "the watch back on stood aside before any dose"
verdict
