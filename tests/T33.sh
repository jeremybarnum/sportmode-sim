#!/bin/sh
# T33 — The watch finds the phone ran the pod, and the phone does not answer (control row 29). A Take
# Back on the phone while the link to the watch is down: the phone takes the pod and its stop cannot
# reach the watch. The phone then leaves the pod's reach, which frees the pod's one connection (while
# the phone holds it the watch cannot connect at all). The watch's next cycle meets the pod's session
# count ahead; its driver stops. It asks
# the phone and hears nothing. Silence never moves the pod: the watch stays stopped, tells the looper
# once and asks again; when the link is back the stop arrives and it stands aside. Needs a pod
# simulator that answers a stale session count with a resync.
TEST=T33
. "$(dirname "$0")/lib.sh"
set -u

say "$TEST — the watch finds the phone ran the pod; the phone silent"
reset

say "Start on the watch; one loop cycle"
start=$(now)
start_loan "$start"
wait_for watch "$start" 'cycle computed,' 400

say "Link down; Take Back on the phone"
sim link down
tap=$(now)
take_back
wait_for phone "$tap" 'take-back: pod link up' 180
sleep 20
say "Phone out of the pod's reach: the pod's connection is free for the watch"
sim phone away

say "The watch's next cycle meets the phone's sessions; it asks, the phone is silent"
wait_for watch "$tap" 'found another controller using the pod and stopped' 600
wait_for watch "$tap" 'staying off the pod and telling the looper' 600
told=$(now)
wait_reading "$told" 400
sleep 20

say "Phone back, link up: the phone's stop arrives"
up=$(now)
sim phone back
sim link up
wait_for watch "$up" 'phone took the pod back|stood aside|loan closed' 300

say "Checks"
expect watch "$tap" 'found another controller using the pod and stopped' "the watch's driver stopped"
expect watch "$tap" 'staying off the pod and telling the looper' "silence: the watch stayed stopped and told the looper"
expect_count watch "$tap" 'staying off the pod and telling the looper' 1 "told once"
expect_none_between watch "$tap" "$up" 'taking control again' "the watch did not take the pod on silence"
expect_none_between watch "$told" "$up" '\[dose\] enacting' "the watch sent the pod nothing while stopped"
expect watch "$up" 'phone took the pod back|stood aside|loan closed' "the stop arrived and the watch stood aside"
verdict
