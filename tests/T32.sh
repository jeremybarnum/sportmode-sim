#!/bin/sh
# T32 — The phone back after a watch-only Start, the watch dead (control rows 28 and 18). The phone's pod
# driver stops at the pod's session count; the phone asks the watch and hears nothing. Silence never moves
# the pod: the phone stays off it, shows the loan as probable and tells the looper at once. The tap on the
# banner takes the pod back and counts what the watch gave. Needs a pod simulator that answers a stale
# session count with a resync.
TEST=T32
. "$(dirname "$0")/lib.sh"
set -u

say "$TEST — phone back after a watch-only Start, the watch dead"
"$SIM" glucose 160 >/dev/null
reset

say "Phone out of reach; offline start on the watch; two watch cycles"
sim phone away
start=$(now)
offline_start "$start"
wait_for watch "$start" 'cycle computed,' 720 2

say "Watch off; phone back: its driver stops, the watch is silent"
sim watch off
pb=$(now)
sim phone back
wait_for phone "$pb" 'found another controller using the pod' 400
wait_for phone "$pb" 'standing aside for a loan only the pod shows' 400
sleep 30

say "Take the pod back on the phone"
tap=$(now)
take_back
wait_for phone "$tap" 'take-back: pod link up' 180
sleep 20

say "Watch back on"
on=$(now)
sim watch on
wait_for watch "$on" 'phone took the pod back|stood aside|loan closed' 300

say "Checks"
expect phone "$pb" 'asking the watch whether it holds the pod' "the phone asked the watch"
expect phone "$pb" 'standing aside for a loan only the pod shows' "silence: the phone stood aside"
expect_none_between phone "$pb" "$tap" 'taking control of the pod again|keeps the pod and keeps looping' "the phone did not take the pod on silence"
expect_between_none phone "$pb" '.' 'take-back: pod link up' 'temp basal enacted|enacting|MANUAL BOLUS|automatic bolus' "the phone sent the pod nothing before the tap"
note=$(python3 "$root/tests/notifications.py" "$PHONE_SIM_ID" --since "$pb" delivered | grep "	Watch Probably Looping	" | head -1)
[ -n "$note" ] && pass "the phone posted \"Watch Probably Looping\"" "$note" || fail "the phone posted \"Watch Probably Looping\"" "no such notification since $pb"
expect_none phone "$pb" 'Watch May Not Be Looping' "no second notice for the same silence"
expect phone "$tap" 'take-back: pod link up' "the tap took the pod"
expect watch "$on" 'phone took the pod back|stood aside|loan closed' "the watch back on stood aside"
"$SIM" glucose 115 >/dev/null
verdict
