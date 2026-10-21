#!/bin/sh
# P16 — An End that gives up. When the hand-back's 2-minute budget runs out and the loan carries on,
# the watch posts exactly one notification, "Couldn't End Sport Mode", with the reason, and its glance
# shows the same sentence until the next End. (a) The phone out of touch (the link cut): the body says
# the iPhone isn't reachable. (b) The phone in touch but its answers arriving after the budget (the
# link 150 s slow): the generic or reopen-Loop body. Each time the loan is still running, and a later
# End goes through.
TEST=P16
. "$(dirname "$0")/lib.sh"
set -u

say "$TEST — an End that gives up"
reset
closed_loop_on

say "(a) Start; the link cut; End"
a=$(now)
start_loan "$a"
sleep 15
sim link down
watch_main
ea=$(now)
ui watch tap End
wait_for watch "$ea" "alert\\] ISSUED .*Couldn't End Sport Mode" 200
watch_shows_text "End didn.t go through|Tap End again" && glance_a=yes || glance_a=no
sim link up
sleep 5
watch_main
ea2=$(now)
ui watch tap End
wait_for watch "$ea2" 'CLOSED — ' 120

say "(b) A new loan; the link 150 s slow; End"
reset
b=$(now)
start_loan "$b"
sleep 15
sim link slow 150
watch_main
eb=$(now)
ui watch tap End
wait_for watch "$eb" "alert\\] ISSUED .*Couldn't End Sport Mode" 200
sim link normal
say "let the late messages land, then End again"
sleep 160
watch_main
eb2=$(now)
ui watch tap End
wait_for watch "$eb2" 'CLOSED — ' 120

say "Checks"
expect_between watch "$ea" "$ea2" "alert\\] ISSUED .*Couldn't End Sport Mode: Your iPhone isn.t reachable" "(a) one notification, with the iPhone-not-reachable reason"
c=$(lines watch "$ea" "alert\\] ISSUED .*Couldn't End Sport Mode" | awk -v u="$ea2" '$1 < u' | wc -l | tr -d ' ')
[ "$c" = 1 ] && pass "(a) exactly one such notification" "" || fail "(a) exactly one such notification ($c)" ""
expect_none_between watch "$ea" "$ea2" 'CLOSED — |REVOKED' "(a) the loan carried on"
[ "$glance_a" = yes ] && pass "(a) the glance showed the sentence" "" || fail "(a) the glance showed the sentence" "not in the watch's element tree"
expect_between watch "$eb" "$eb2" "alert\\] ISSUED .*Couldn't End Sport Mode" "(b) the notification when the answers came too late"
expect_none_between watch "$eb" "$eb2" 'CLOSED — |REVOKED' "(b) the loan carried on"
expect watch "$eb2" 'CLOSED — ' "(b) a later End went through"
verdict
