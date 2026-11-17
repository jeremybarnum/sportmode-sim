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
wait_reading "$start" 300 2

say "Phone back: its driver stops at first contact; it asks the watch and stands aside"
pb=$(now)
sim phone back
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
"$SIM" glucose 115 >/dev/null
verdict
