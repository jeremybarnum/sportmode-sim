#!/bin/sh
# T19 — The watch back after the phone took over on silence. The phone refuses a revived watch's
# claim to a loan that started before its takeover; the watch stands aside before any dose.
TEST=T19
. "$(dirname "$0")/lib.sh"
set -u

say "$TEST — revived watch after the phone took over"
reset

say "Phone out of reach; offline start; 0.5 U bolus; watch off"
sim phone away
start=$(now)
offline_start "$start"
watch_bolus 0.5
sim watch off

say "Phone back: it books the insulin and keeps the pod (up to 10 minutes)"
pb=$(now)
sim phone back
wait_for phone "$pb" 'this phone keeps the pod and keeps looping' 600

say "Watch back on"
on=$(now)
sim watch on
wait_for watch "$on" 'resumed loan' 120
wait_for watch "$on" 'phone took the pod back|stood aside|loan closed' 300
sleep 30

say "Checks"
expect phone "$pb" 'this phone keeps the pod and keeps looping' "phone kept the pod after no answer"
expect watch "$on" 'resumed loan' "watch resumed"
expect watch "$on" 'told the phone this watch holds the pod' "watch asked the phone first"
expect watch "$on" 'phone took the pod back|stood aside' "watch stood aside"
expect_between_none watch "$on" 'resumed loan' 'phone took the pod back|stood aside' 'dosemath|enacting' "no dose before the phone's answer"
expect phone "$on" 'estimate retired' "the watch's records retired the phone's estimate"
expect phone "$on" 'back in control of the pod' "phone back in control of the pod after the records came home"
verdict
