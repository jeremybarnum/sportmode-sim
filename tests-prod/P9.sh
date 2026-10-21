#!/bin/sh
# P9 — Take Back with the watch silent past 330 s: the phone forces the take-back at once.
# Pending decision: single-path Take Back.
TEST=P9
. "$(dirname "$0")/lib.sh"
set -u

say "$TEST — Take Back with the watch silent"
reset

say "Start; once active, the watch off for 6 minutes"
start=$(now)
start_loan "$start"
sleep 20
sim watch off
sleep 360
tb=$(now)
take_back
wait_for phone "$tb" 'force reclaim SALVAGE' 30

say "The watch back on"
sim watch on
drivers
wait_for watch "$tb" 'REVOKED|recovered|CLOSED' 180

say "Checks"
expect phone "$tb" 'reclaim ladder DEAD' "the phone took the dead path"
expect_within phone "$tb" 'force reclaim SALVAGE' 5 "forced at once"
expect_none phone "$tb" 'reclaim revoke RESENT' "no resend on the dead path"
verdict
