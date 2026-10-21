#!/bin/sh
# P12 — Start with the phone out of reach: the watch waits 8 s, not its usual 25, before offering an
# offline start.
TEST=P12
. "$(dirname "$0")/lib.sh"
set -u

say "$TEST — Start with the phone out of reach"
reset

say "The phone out of reach; Start on the watch"
sim phone away
sleep 5
start=$(tap_start)
ui watch wait 20 "Start Anyway"
offered=$(now)

say "Cancel; the phone back"
ui watch tap Cancel
sim phone back

say "Checks"
expect watch "$start" 'REQUEST sent .*phone unreachable — short 8s timeout' "the watch knew the phone was out of reach"
expect_within watch "$start" 'REQUEST TIMED OUT — offering offline start' 12 "the offline start offered after about 8 s"
expect_none watch "$start" 'SEIZE confirmed' "nothing started on Cancel"
verdict
