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
wait_for phone "$pb" 'keeps the pod' 600

say "Watch back on"
on=$(now)
sim watch on
wait_for watch "$on" 'RESUMED' 120
wait_for watch "$on" 'REVOKED|stood aside|CLOSED — ' 300
sleep 30

say "Checks"
expect phone "$pb" 'keeps the pod' "phone kept the pod after no answer"
expect watch "$on" 'RESUMED' "watch resumed"
expect watch "$on" 'statusReport sent' "watch asked the phone first"
expect watch "$on" 'REVOKED|stood aside' "watch stood aside"
expect_between_none watch "$on" 'RESUMED' 'REVOKED|stood aside' 'dosemath|enacting' "no dose before the phone's answer"
expect phone "$on" 'estimate RETIRED' "the watch's records retired the phone's estimate"
expect phone "$on" 'reclaim VERIFIED' "phone back in control of the pod after the records came home"
verdict
