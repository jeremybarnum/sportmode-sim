#!/bin/sh
# P7 — A silent watch during a loan, warn only. With the watch off and the phone reading its own sensor,
# the phone notes the silence at 15 minutes and warns "Watch Not Reporting" at about 20, 40 and 60
# minutes (within 30 s of a mark counts as reached), and never takes the pod back on a timer. About 70 minutes in real time.
# Warn only: ruled for this build (2026-10-21). (Not covered: no warning while the phone's own
# glucose is stale, which needs the phone's sensor stopped for an hour.)
TEST=P7
. "$(dirname "$0")/lib.sh"
set -u

say "$TEST — a silent watch, warn only"
reset

say "Start; once active, the watch off for 65 minutes"
start=$(now)
start_loan "$start"
sleep 20
off=$(now)
sim watch off
wait_for phone "$off" 'warning 3 of 3 issued' 4200

say "The watch back on: its app relaunches, which ends the loan, and the phone takes the pod back"
tb=$(now)
sim watch on
drivers
wait_for phone "$tb" 'reclaim VERIFIED' 360

say "Checks"
expect_within phone "$off" 'watch SILENT — no report for' 1020 "the phone noted the silence (about 15 minutes)"
s1=$(seconds_to phone "$off" 'warning 1 of 3 issued'); s2=$(seconds_to phone "$off" 'warning 2 of 3 issued'); s3=$(seconds_to phone "$off" 'warning 3 of 3 issued')
within() { awk -v s="$1" -v a="$2" -v b="$3" 'BEGIN { exit !(s >= a && s <= b) }'; }
if [ -n "$s1" ] && within "$s1" 1080 1320; then pass "first warning at about 20 minutes ($s1 s)" ""; else fail "first warning at about 20 minutes (${s1:-never} s)" ""; fi
if [ -n "$s2" ] && within "$s2" 2280 2520; then pass "second warning at about 40 minutes ($s2 s)" ""; else fail "second warning at about 40 minutes (${s2:-never} s)" ""; fi
if [ -n "$s3" ] && within "$s3" 3480 3720; then pass "third warning at about 60 minutes ($s3 s)" ""; else fail "third warning at about 60 minutes (${s3:-never} s)" ""; fi
expect_none_between phone "$off" "$tb" 'reclaim ladder|force reclaim|R37 audit armed|settle:' "no take-back on a timer while the watch was silent"
verdict
