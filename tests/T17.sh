#!/bin/sh
# T17 — The watch back from off beside a phone that took the pod back. The watch asks first; the
# phone's answer stands it aside before any dose.
TEST=T17
. "$(dirname "$0")/lib.sh"
set -u

say "$TEST — watch back from off after a take-back"
reset

say "Start on the watch, one loop cycle"
start=$(now)
start_loan "$start"
wait_for watch "$start" 'CYCLE VERDICT computed=ok' 400

say "Watch off; the phone takes the pod back and boluses 0.5 U"
sim watch off
sleep 3
tb=$(now)
take_back
wait_for phone "$tb" 'take-back: pod link up' 60
sleep 20
dismiss_alert
phone_bolus 0.5
sleep 20

say "Watch back on"
on=$(now)
sim watch on
wait_for watch "$on" 'RESUMED' 120
wait_for watch "$on" 'REVOKED|stood aside' 300

say "Checks"
expect watch "$on" 'RESUMED' "watch resumed"
# The watch asks before looping, unless the phone's queued stop, delivered at launch, stood it aside
# before it needed to; either way nothing doses before the answer (the next check).
expect watch "$on" 'statusReport sent|REVOKED' "watch asked the phone first, or the phone's stop landed first"
expect watch "$on" 'REVOKED|stood aside' "watch stood aside"
expect_between_none watch "$on" 'RESUMED' 'REVOKED|stood aside' 'dosemath|enacting' "no dose before the phone's answer"
verdict
