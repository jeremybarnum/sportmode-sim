#!/bin/sh
# T10 — When the offline start is offered. The Start's request is the question; when the phone
# does not answer within 10 s, a watch holding the phone's standing copy offers to start without
# it: (a) with the phone out of reach, (c) with the phone in reach but its app not running.
TEST=T10
. "$(dirname "$0")/lib.sh"
set -u

say "$TEST — when the offline start is offered"
reset

say "(a) Phone out of reach; Start on the watch"
sim phone away
a=$(tap_start)
ui watch wait 20 "Start Anyway"
ui watch tap Cancel
sim phone back
sleep 15
# A Start cancelled at the offer must not start later: the queued request is cancelled with it.
ghost=$(lines watch "$a" 'GRANT received' | head -1)
[ -n "$ghost" ] && reset

say "(c) Phone app not running; Start on the watch"
sim quit phone
sleep 3
c=$(tap_start)
"$UI" watch wait 20 "Start Anyway" >/dev/null 2>&1 && ui watch tap Cancel
sim launch phone
sleep 10

say "Checks"
expect_within watch "$a" 'offering offline start' 12 "(a) offered after the 10 s wait, phone out of reach"
# A message to a phone app that is not running can wake it (the Simulator does), and then it answers:
# a grant, or a denial while it is still reaching its pod. Either is an answer, so no offer.
if [ -n "$(lines watch "$c" 'GRANT received|DENIED by phone')" ]; then
	pass "(c) the phone app woke to the request and answered: the offer is not reached this way here" "$(lines watch "$c" 'GRANT received|DENIED by phone' | head -1)"
else
	expect_within watch "$c" 'offering offline start' 12 "(c) offered after the 10 s wait, phone app not running"
fi
expect_none watch "$a" 'SEIZE confirmed' "no offline start without the confirm"
if [ -z "$ghost" ]; then pass "(a) the cancelled Start did not start a loan when the phone came back" ""
else fail "(a) the cancelled Start did not start a loan when the phone came back" "$ghost"; fi
verdict
