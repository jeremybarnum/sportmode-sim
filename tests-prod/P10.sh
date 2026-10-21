#!/bin/sh
# P10 — A forced Take Back (the watch not answering) with the pod out of reach: the phone cannot
# verify the watch's delivery, and when its 5-minute settle runs out it says so ("Watch Session
# Unverified") and opens the loop. Pending decision: single-path Take Back.
TEST=P10
. "$(dirname "$0")/lib.sh"
set -u

say "$TEST — a forced Take Back with the pod out of reach"
reset

say "Start; once active, the link cut and the pod out of reach; Take Back"
start=$(now)
start_loan "$start"
sleep 20
sim link down
sim pod away
tb=$(now)
take_back
wait_for phone "$tb" 'force reclaim SALVAGE' 60
say "The settle runs out (5 minutes)"
wait_for phone "$tb" 'audit NEVER RAN' 400

say "The pod and the link back"
sim pod back
sim link up

say "Checks"
expect phone "$tb" 'force reclaim SALVAGE' "the take-back was forced"
expect phone "$tb" 'R37: audit NEVER RAN .*Session UNVERIFIED, loop OPENS' "unverified at 5 minutes, the loop opened"
expect_none phone "$tb" 'R37 audit CLEAN' "no clean audit claimed"
verdict
