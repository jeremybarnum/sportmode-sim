#!/bin/sh
# P5 — The watch app relaunched during a loan ends the loan: "Sport Mode Ended", the recovered offer
# resent every 15 s until the phone acknowledges it, and the phone takes the pod back. (b): the same
# with the phone out of reach for a minute first; the offers wait and land when it is back.
TEST=P5
. "$(dirname "$0")/lib.sh"
set -u

say "$TEST — the watch app relaunched during a loan"
reset

say "(a) Start; once active, the watch app ends and opens again"
a=$(now)
start_loan "$a"
sleep 20
qa=$(now)
sim quit watch
sleep 3
sim launch watch
drivers
wait_for phone "$qa" 'reclaim VERIFIED' 180

say "(b) A new loan; the phone out of reach; the watch app ends and opens again; the phone back after a minute"
reset
b=$(now)
start_loan "$b"
sleep 20
sim phone away
qb=$(now)
sim quit watch
sleep 3
sim launch watch
drivers
sleep 60
back=$(now)
sim phone back
wait_for phone "$back" 'reclaim VERIFIED' 240

say "Checks"
expect watch "$qa" 'alert\] ISSUED .*sessionEnded' "(a) the relaunched watch ended the loan (Sport Mode Ended)"
expect watch "$qa" 'hand-back offer attempt' "(a) the recovered offer went out"
expect phone "$qa" 'offer RX .*released=final' "(a) the phone took the recovered offer"
expect phone "$qa" 'reclaim VERIFIED' "(a) the phone took the pod back"
expect_clean phone "$qa" 'reconcile\[AUTHORITATIVE\]' "(a) the phone's audit"
expect_none watch "$qa" 'ACTIVE — epoch' "(a) no resume after the relaunch"
expect watch "$qb" 'iPhone UNREACHABLE|hand-back offer attempt [2-9]' "(b) the offers waited while the phone was away"
expect_none_between phone "$qb" "$back" 'offer RX' "(b) nothing reached the phone while it was away"
expect phone "$back" 'offer RX .*released=final' "(b) the offer landed when the phone was back"
expect phone "$back" 'reclaim VERIFIED' "(b) the phone took the pod back"
verdict
