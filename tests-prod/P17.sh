#!/bin/sh
# P17 — A Take Back the watch answers, with the pod out of reach for longer than the phone's 5-minute
# settle, then a new loan. Found 2026-10-21 (P10's first run): the phone cleared its settle at 5
# minutes with no notice, kept the hand-back audit open, granted the next loan, and ran the old audit
# on the next loan's pod reading, so the pod's scheduled basal in the gap read as unexplained insulin
# ("R32 OPEN LOOP"). Pass: no stale audit carried into the next loan, and no false open loop.
TEST=P17
. "$(dirname "$0")/lib.sh"
set -u

say "$TEST — Take Back with the pod out of reach past the settle, then a new loan"
reset

say "Start; once active, the pod out of reach; Take Back (the watch answers)"
s1=$(now)
start_loan "$s1"
sleep 20
sim pod away
tb=$(now)
take_back
wait_for watch "$tb" 'REVOKED' 60
wait_for phone "$tb" 'offer RX .*released=final' 60
epoch1=$(lines phone "$tb" 'offer RX .*released=final' | head -1 | sed -n 's/.*\] e\([0-9]*\) .*/\1/p')
say "The settle runs out (5 minutes and a half)"
sleep 330

say "The pod back; a new loan, ended on the watch"
sim pod back
reset
s2=$(now)
start_loan "$s2"
wait_for watch "$s2" 'cycle OK' 360
watch_main
e2=$(now)
ui watch tap End
wait_for phone "$e2" 'reclaim VERIFIED' 180
sleep 5

say "Checks"
l=$(lines phone "$s2" "e$epoch1 reconcile\\[AUTHORITATIVE\\]" | head -1)
if [ -z "$l" ]; then pass "the take-back's audit (e$epoch1) was not run on the next loan's reading" ""
else fail "the take-back's audit (e$epoch1) was not run on the next loan's reading" "$l"; fi
expect_none phone "$s2" 'R32 OPEN LOOP' "no open loop from the gap's scheduled basal"
expect_clean phone "$e2" 'reconcile\[AUTHORITATIVE\]' "the new loan's own audit"
verdict
