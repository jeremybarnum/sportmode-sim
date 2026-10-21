#!/bin/sh
# P17 — A Take Back the watch answers, with the pod out of reach for longer than the phone's 5-minute
# settle, then a new loan. Found 2026-10-21 (P10's first run): the phone cleared its settle at 5
# minutes with no notice, kept the hand-back audit open, granted the next loan, and ran the old audit
# on the next loan's pod reading, so the pod's scheduled basal in the gap read as unexplained insulin
# ("R32 OPEN LOOP"). In P17's own first run the next loan's audit replaced it instead, and the
# take-back's audit never ran at all, with no notice. Pass: the take-back's audit is concluded,
# verified or reported unverified, before the next loan; no false open loop.
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
say "A Start while the take-back's insulin check is pending: refused"
sleep 30
watch_close_sheets
r=$(now)
tap_start >/dev/null || true
sleep 10
watch_shows_text "still checking the last session.s insulin" && pending_note=yes || pending_note=no

say "The settle runs out (5 minutes and a half from the take-back)"
sleep 270

say "The pod back; a new loan, ended on the watch"
sim pod back
reset
closed_loop_on
s2=$(now)
start_loan "$s2"
wait_for watch "$s2" 'cycle OK' 360
watch_main
e2=$(now)
ui watch tap End
wait_for phone "$e2" 'reclaim VERIFIED' 180
sleep 5

say "Checks"
expect phone "$r" 'grant REFUSED — this session.s insulin check is still pending' "a Start while the check was pending was refused"
[ "$pending_note" = yes ] && pass "the watch said the iPhone is still checking the last session's insulin" "" || fail "the watch said the iPhone is still checking the last session's insulin" "not on the glance"
expect_between phone "$tb" "$s2" "e$epoch1 (reconcile\\[AUTHORITATIVE\\]|R3[37]: audit NEVER RAN)" "the take-back's audit (e$epoch1) concluded, verified or reported unverified, before the next loan"
expect_between phone "$tb" "$s2" 'R33: audit NEVER RAN \(handback\)' "the answered take-back's check ended unverified at the settle limit"
l=$(lines phone "$s2" "e$epoch1 reconcile\\[AUTHORITATIVE\\]" | head -1)
if [ -z "$l" ]; then pass "the take-back's audit (e$epoch1) was not run on the next loan's reading" ""
else fail "the take-back's audit (e$epoch1) was not run on the next loan's reading" "$l"; fi
expect_none phone "$s2" 'R32 OPEN LOOP' "no open loop from the gap's scheduled basal"
expect_clean phone "$e2" 'reconcile\[AUTHORITATIVE\]' "the new loan's own audit"
verdict
