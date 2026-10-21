#!/bin/sh
# P10 — Take Back with the pod out of reach: the phone cannot verify the watch's delivery, and at
# 5 minutes it says so ("Watch Session Unverified") and opens the loop. Pending decision: single-path
# Take Back.
TEST=P10
. "$(dirname "$0")/lib.sh"
set -u

say "$TEST — Take Back with the pod out of reach"
reset

say "Start; once active, the pod out of reach; Take Back"
start=$(now)
start_loan "$start"
sleep 20
sim pod away
tb=$(now)
take_back
wait_for phone "$tb" 'audit NEVER RAN' 400

say "The pod back"
sim pod back

say "Checks"
expect watch "$tb" 'REVOKED' "the watch let the pod go"
expect phone "$tb" 'R37: audit NEVER RAN .*Session UNVERIFIED, loop OPENS' "unverified, the loop opened"
expect_none phone "$tb" 'R37 audit CLEAN' "no clean audit claimed"
verdict
