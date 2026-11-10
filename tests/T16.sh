#!/bin/sh
# T16 — A granted loan, the watch shut down, the phone near the body. The phone asks the silent
# watch and, with no answer, tells the looper the watch may not be looping, once; it does not take
# the pod. A tap on Take Back takes it, counting the watch's insulin; the watch back on stands aside.
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
wait_for phone "$off" 'telling the looper the watch may not be looping' 300

say "The phone asks again, two more sensor readings: it asks and does not tell the looper again"
told=$(now)
wait_for phone "$told" 'asking the watch whether it holds the pod' 400
wait_reading "$told" 700 2
sleep 30

say "Take the pod back on the phone"
tap=$(now)
take_back
wait_for phone "$tap" 'temp cancelled' 180

say "Watch back on"
on=$(now)
sim watch on
wait_for watch "$on" 'phone took the pod back|stood aside|loan closed' 300

say "Checks"
expect phone "$off" 'asking the watch whether it holds the pod' "phone asked the silent watch"
expect phone "$told" 'asking the watch whether it holds the pod' "phone asked again after telling the looper"
expect_count phone "$off" 'telling the looper the watch may not be looping' 1 "phone told the looper once"
note=$(python3 "$root/tests/notifications.py" "$PHONE_SIM_ID" --since "$off" delivered | grep "	Watch May Not Be Looping	" | head -1)
[ -n "$note" ] && pass "the phone posted \"Watch May Not Be Looping\"" "$note" || fail "the phone posted \"Watch May Not Be Looping\"" "no such notification since $off"
expect_none phone "$off" 'taking the pod back: no answer' "phone did not take the pod on silence"
expect_none_between phone "$off" "$tap" 'take-back: pod link up' "the pod stayed lent until the tap"
expect phone "$tap" 'take-back: pod link up' "the tap took the pod"
# The watch's records may reach the phone before the watch goes off (then the take-back expects the
# bolus and the residual is near zero) or not (then the residual books it): either way, delivered.
l=$(lines phone "$tap" 'take-back check: delivered' | tail -1)
verdict_ok=$(echo "$l" | awk '{ d = 0; r = 9
	if (match($0, /delivered[ =][0-9.]+/)) d = substr($0, RSTART + 10, RLENGTH - 10) + 0
	if (match($0, /residual[ =][+-]?[0-9.]+/)) r = substr($0, RSTART + 9, RLENGTH - 9) + 0
	if (d >= 0.45 && ((r >= -0.2 && r <= 0.2) || (r >= 0.3 && r <= 0.7))) print "yes" }')
if [ "$verdict_ok" = yes ]; then pass "take-back accounted for the watch's bolus" "$l"
else fail "take-back accounted for the watch's bolus" "${l:-no take-back check line}"; fi
expect phone "$tap" 'temp cancelled' "watch's temp ended"
expect_between_none watch "$on" 'resumed loan|app launched' 'phone took the pod back|stood aside|loan closed' 'dosemath|enacting' "the watch back on stood aside before any dose"
verdict
