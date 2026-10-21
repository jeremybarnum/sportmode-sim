#!/bin/sh
# P8 — Take Back on the phone with the watch live. (a) The watch answers: revoked, the records come
# home, the audit is clean. (b) The watch does not answer (the link cut): the revoke is resent at
# +10 s and the phone forces the take-back at +25 s. Pending decision: single-path Take Back.
TEST=P8
. "$(dirname "$0")/lib.sh"
set -u

say "$TEST — Take Back with the watch live"
reset

say "(a) Start; once active, Take Back on the phone"
a=$(now)
start_loan "$a"
sleep 20
ta=$(now)
take_back
wait_for watch "$ta" 'REVOKED' 60
wait_for phone "$ta" 'reclaim VERIFIED' 360

say "(b) A new loan; the link cut; Take Back"
reset
b=$(now)
start_loan "$b"
sleep 20
sim link down
tb=$(now)
take_back
wait_for phone "$tb" 'R37 audit armed' 60
sleep 10
sim link up
wait_for watch "$tb" 'REVOKED' 120

say "Checks"
expect phone "$ta" 'reclaim ladder LIVE' "(a) the phone took the live path"
expect watch "$ta" 'REVOKED' "(a) the watch let the pod go"
expect_clean phone "$ta" 'reconcile\[AUTHORITATIVE\]' "(a) the audit over the watch's window"
expect phone "$tb" 'reclaim ladder LIVE' "(b) the phone took the live path"
expect_within phone "$tb" 'reclaim revoke RESENT \(attempt 2 of 2\)' 15 "(b) the revoke resent at about +10 s"
expect_within phone "$tb" 'R37 audit armed' 32 "(b) the take-back forced at about +25 s"
expect watch "$tb" 'REVOKED' "(b) the watch let the pod go once the link was back"
expect phone "$tb" 'R37 audit (CLEAN|WARN|OPEN)' "(b) the forced take-back's audit ruled"
verdict
