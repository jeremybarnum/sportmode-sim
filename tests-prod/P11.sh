#!/bin/sh
# P11 — An offline start with the phone out of reach, then the phone back: the watch prompts the
# reunion, and handing back gets the loan adopted by the phone (the retro-acknowledgement) and the pod
# home with a clean audit.
TEST=P11
. "$(dirname "$0")/lib.sh"
set -u

say "$TEST — offline start, then the phone back"
reset

say "The phone out of reach; Start, then Start Anyway"
sim phone away
sleep 5
start=$(now)
offline_start "$start"

say "A watch loop cycle on its own reading (up to 6 minutes)"
wait_for watch "$start" 'cycle OK' 360

say "The phone back; the reunion prompt; Hand Back"
back=$(now)
sim phone back
ui watch wait 120 "Hand Back"
ui watch tap "Hand Back"
wait_for phone "$back" 'reclaim VERIFIED' 240

say "Checks"
expect watch "$start" 'REQUEST TIMED OUT — offering offline start' "the offline start was offered"
expect watch "$start" 'SEIZE confirmed' "the watch took the pod with its standing copy"
expect watch "$start" 'seized loan ACTIVE' "the seized loan ran"
expect watch "$back" 'REUNION PROMPT' "the reunion prompt came when the phone was back"
expect phone "$back" 'RETRO-ACK — offer for a SEIZED loan' "the phone adopted the seized loan"
expect phone "$back" 'reclaim VERIFIED' "the phone took the pod back"
expect_clean phone "$back" 'reconcile\[AUTHORITATIVE\]' "the phone's audit over the watch's window"
verdict
