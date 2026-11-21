#!/bin/sh
# T19 — The watch back after the phone took the pod back (control rows 28, 18, 19). A watch-only Start, a
# watch bolus, the watch off; the phone back finds the pod ran by another controller, the watch silent:
# it stays off the pod and tells (silence never moves the pod), and the looper's tap takes the pod back.
# The phone never heard the watch's loan number, so the take-back keeps its time: the revived watch's
# claim to a loan started before it is refused, and the watch stands aside before any dose.
TEST=T19
. "$(dirname "$0")/lib.sh"
set -u

say "$TEST — revived watch after the phone took the pod back"
reset

say "Phone out of reach; offline start; 0.5 U bolus; watch off"
sim phone away
start=$(now)
offline_start "$start"
watch_bolus 0.5
sim watch off

say "Phone back: it stays off the pod and tells (up to 10 minutes)"
pb=$(now)
sim phone back
wait_for phone "$pb" 'standing aside for a loan only the pod shows' 600
sleep 20

say "Take the pod back on the phone"
tap=$(now)
take_back
wait_for phone "$tap" 'take-back: pod link up' 180
sleep 20

say "Watch back on"
on=$(now)
sim watch on
wait_for watch "$on" 'resumed loan' 120
wait_for watch "$on" 'phone took the pod back|stood aside|loan closed' 300
sleep 30

say "Checks"
expect phone "$pb" 'standing aside for a loan only the pod shows' "silence: the phone stood aside and told"
expect_none phone "$pb" 'this phone keeps the pod and keeps looping' "the phone did not take the pod on silence"
expect phone "$tap" 'take-back: pod link up' "the tap took the pod"
expect phone "$tap" 'back in control of the pod' "phone back in control of the pod"
expect watch "$on" 'resumed loan' "watch resumed"
expect watch "$on" 'told the phone this watch holds the pod' "watch asked the phone first"
expect watch "$on" 'phone took the pod back|stood aside' "watch stood aside"
expect_between_none watch "$on" 'resumed loan' 'phone took the pod back|stood aside' 'dosemath|enacting' "no dose before the phone's answer"
expect phone "$on" 'telling the watch again to stop this closed loan|refus' "the phone refused the revived loan with the stop"
expect phone "$on" 'estimate retired' "the watch's records came home and retired the phone's estimate"
expect phone "$on" 'back in control of the pod' "the phone kept the pod"
expect_none phone "$on" 'standing aside for a loan the watch started' "the phone did not stand aside for the revived loan"
verdict
