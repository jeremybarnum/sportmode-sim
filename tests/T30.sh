#!/bin/sh
# T30 — The phone back within minutes of a watch-only Start, the watch alive. The phone's pod reading is
# under the driver's 6 minutes of freshness, so its first cycle would command the pod without reading it.
# With the driver's stop at a session resync nobody expected, the phone's first contact finds another
# controller and sends the pod nothing; the phone asks the watch, the watch answers, the phone stands
# aside (control rows 28 and 17). Needs a pod simulator that answers a stale session count with a resync.
TEST=T30
. "$(dirname "$0")/lib.sh"
set -u

say "$TEST — phone back within minutes of a watch-only Start"
"$SIM" glucose 160 >/dev/null
reset

say "Phone out of reach; offline start on the watch; two watch cycles"
sim phone away
start=$(now)
offline_start "$start"
sleep 130

# The watch's word must not reach the phone before the phone reaches the pod, or the phone stands aside
# by the ordinary route (its records) and the driver's stop is never exercised: the phone-watch link
# stays down until the driver has stopped, then comes back and the watch answers.
say "Phone back with its link to the watch down: its driver stops at first contact"
pb=$(now)
sim link down
sim phone back
wait_for phone "$pb" 'found another controller using the pod' 400
say "Link back up: the watch answers and the phone stands aside"
sim link up
wait_for phone "$pb" 'standing aside for a loan the watch started without this phone' 300
sleep 20

say "Checks"
o=$(oslog "$pb" "another controller has used this pod")
[ -n "$o" ] && pass "the phone's driver stopped at the resync" "$(echo "$o" | head -1)" \
	|| fail "the phone's driver stopped at the resync" "no such line in the phone's system log since $pb"
expect phone "$pb" 'found another controller using the pod' "the phone heard the driver's report"
expect phone "$pb" 'standing aside for a loan the watch started without this phone' "the phone stood aside"
expect_between_none phone "$pb" '.' 'standing aside for a loan the watch started' 'temp basal enacted|enacting|MANUAL BOLUS|automatic bolus' "the phone sent the pod nothing before standing aside"
expect_none watch "$pb" 'phone took the pod back|stood aside' "the watch kept the pod"
expect_none phone "$pb" 'standing aside for a loan only the pod shows' "the watch's answer, not silence, made the phone stand aside"
"$SIM" glucose 115 >/dev/null
verdict
