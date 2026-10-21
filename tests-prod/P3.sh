#!/bin/sh
# P3 — The watch silent through the takeover. The phone asks at +20 s whether the grant arrived; with
# no answer it waits out its 5-minute timer ("Watch Loan Not Confirmed", a notification scheduled at the
# grant), asks again, and takes the pod back about 15 s later. (The other half, a grant lost on the way
# while the watch stays in touch, needs a link that drops one message; it is not scripted.)
TEST=P3
. "$(dirname "$0")/lib.sh"
set -u

say "$TEST — the watch silent through the takeover"
reset

say "The pod out of reach so the takeover runs on; Start; then the watch off"
sim pod away
start=$(now)
tap_start >/dev/null
wait_for phone "$start" 'GRANT — releasing pod BLE' 30
granted=$(lines phone "$start" 'GRANT — releasing pod BLE' | head -1 | cut -c1-12)
wait_for watch "$start" 'takeover ladder start' 30
sim watch off
sim pod back

say "The phone's timer runs out (about 5 minutes after the grant)"
wait_for phone "$granted" 'settle: link up|reclaim VERIFIED' 420

say "The watch back on"
sim watch on
drivers

say "Checks"
expect_within phone "$granted" 'grant unconfirmed after 20s' 25 "the phone asked at +20 s"
expect_none phone "$granted" 'grant CONFIRMED LOST' "no answer came from the silent watch"
s=$(seconds_to phone "$granted" 'settle: link up|reclaim VERIFIED')
if [ -n "$s" ] && awk -v s="$s" -v lo="$(( $(sc 300) - 5 ))" -v hi="$(( $(sc 300) + 45 ))" 'BEGIN { exit !(s >= lo && s <= hi) }'; then pass "the phone took the pod back after its 5-minute timer and 15 s more ($s s after the grant)" ""
else fail "the phone took the pod back after its 5-minute timer and 15 s more (${s:-never} s after the grant)" ""; fi
expect phone "$granted" 'reclaim VERIFIED' "the phone verified the pod"
verdict
