#!/bin/sh
# P4 — A Start interrupted by the watch app ending during the takeover. At relaunch the watch fails
# the takeover to the phone, which takes the pod back. The pod is out of reach so the takeover is still
# under way when the app ends.
TEST=P4
. "$(dirname "$0")/lib.sh"
set -u

say "$TEST — a Start interrupted by the watch app ending"
reset

say "The pod out of reach; Start on the watch"
sim pod away
start=$(now)
tap_start >/dev/null
wait_for watch "$start" 'takeover ladder start' 60

say "The watch app ends during the takeover, and opens again"
sleep 5
quit=$(now)
sim quit watch
sleep 3
sim launch watch
drivers
wait_for watch "$quit" 'START INTERRUPTED' 60

say "The pod back in reach; the phone takes it back"
sim pod back
wait_for phone "$quit" 'reclaim VERIFIED' 360

say "Checks"
expect phone "$start" 'GRANT — releasing pod BLE' "phone granted and released the pod"
expect_none watch "$start" 'ACTIVE — epoch' "the takeover did not finish"
expect watch "$quit" 'START INTERRUPTED — takeover was in flight at relaunch' "the watch failed the takeover at relaunch"
expect phone "$quit" 'listen END \(watch reported takeover failed' "the phone heard the takeover failed"
expect phone "$quit" 'reclaim VERIFIED' "the phone took the pod back"
expect_none phone "$start" 'Watch Loan Not Confirmed|force reclaim' "no notice and no forced take-back"
verdict
