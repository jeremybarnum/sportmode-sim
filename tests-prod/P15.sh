#!/bin/sh
# P15 — The predicted-low warning on the watch during a loan, one decision shared with the phone.
# (a) Glucose falling with no carbs: the watch warns ("[lowbg] WARNED · <title>"). (b) The same fall
# just after a carb entry: no warning while the carbs are recent ("no warning — carbs too recent").
# Needs Predicted Low Warnings on in the phone's Alert Management (and overnight warnings, at night).
# The readings are stepped by the test: held high first, so neither device has warned within the
# snooze, then 8 mg/dL a reading (a 10 mg/dL drop reads as a compression low and is skipped).
# Up to about two hours.
TEST=P15
. "$(dirname "$0")/lib.sh"
set -u

# hold <mg/dL> <readings>: the sensor at a value for that many readings.
hold() {
	local i t
	sim glucose "$1"
	for i in $(seq 1 "$2"); do t=$(now); wait_for watch "$t" 'INGEST src=direct-G7' 330 >/dev/null; done
}

# fall_until <since> <regex> <values...>: one value a reading until the watch logs regex since a time.
fall_until() {
	local since=$1 regex=$2 v t
	shift 2
	for v in "$@"; do
		sim glucose "$v"
		t=$(now)
		wait_for watch "$t" 'INGEST src=direct-G7' 330 >/dev/null
		sleep 10
		[ -n "$(lines watch "$since" "$regex")" ] && return 0
	done
	return 1
}

say "$TEST — the predicted-low warning on the watch"
reset
closed_loop_on

say "(a) Glucose held at 170 for two readings; Start; then down 8 a reading until the watch warns"
hold 170 2
a=$(now)
start_loan "$a"
fall_until "$a" 'lowbg\] WARNED' 162 154 146 138 130 122 114 106 98 90 82 74 66 || say "no warning by 66 mg/dL"
watch_main
ui watch tap End
wait_for watch "$a" 'CLOSED — ' 120

say "(b) Glucose held at 170; 30 g of carbs on the phone; Start; the same fall for six readings"
reset
hold 170 2
phone_carbs 30
phone_home
b=$(now)
start_loan "$b"
fall_until "$b" 'lowbg\] WARNED' 162 154 146 138 130 122 || true
watch_main
ui watch tap End
wait_for watch "$b" 'CLOSED — ' 120
sim glucose sine 120 30

say "Checks"
expect_between watch "$a" "$b" 'lowbg\] WARNED' "(a) the watch warned of a low"
expect watch "$b" 'lowbg\].*no warning — carbs too recent' "(b) no warning while the carbs were recent"
expect_none watch "$b" 'lowbg\] WARNED' "(b) no warning given"
verdict
