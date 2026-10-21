#!/bin/sh
# P15 — The predicted-low warning on the watch during a loan, one decision shared with the phone.
# (a) Glucose falling with no carbs: the watch warns ("[lowbg] WARNED · <title>"). (b) The same fall
# just after a carb entry: no warning while the carbs are recent ("no warning — carbs too recent").
# The sensor's readings are stepped down by the test, one per 5-minute reading; about an hour.
TEST=P15
. "$(dirname "$0")/lib.sh"
set -u

# fall <values...>: each value for one reading, waiting for the watch to read it.
fall() {
	local v t
	for v in "$@"; do
		sim glucose "$v"
		t=$(now)
		wait_for watch "$t" 'INGEST src=direct-G7' 330 >/dev/null
	done
}

say "$TEST — the predicted-low warning on the watch"
reset
sim glucose 150

say "(a) Start; glucose falls from 150 by about 15 a reading"
a=$(now)
start_loan "$a"
fall 140 125 110 95 82 72
wait_for watch "$a" 'lowbg\] WARNED' 330
watch_main
ui watch tap End
wait_for watch "$a" 'CLOSED — ' 120

say "(b) Carbs on the phone; Start; the same fall"
sim glucose 150
reset
phone_carbs 30
b=$(now)
start_loan "$b"
fall 140 125 110 95 82 72
watch_main
ui watch tap End
wait_for watch "$b" 'CLOSED — ' 120
sim glucose sine 120 30

say "Checks"
expect_between watch "$a" "$b" 'lowbg\] WARNED' "(a) the watch warned of a low"
expect watch "$b" 'lowbg\].*no warning — carbs too recent' "(b) no warning while the carbs were recent"
expect_none watch "$b" 'lowbg\] WARNED' "(b) no warning given"
verdict
