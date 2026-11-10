#!/bin/sh
# T6 — Offline start with the watch alive, then back to the phone. The phone adopts a loan it
# never granted; its own window ends at the watch's takeover; the hand-back's check is clean.
TEST=T6
. "$(dirname "$0")/lib.sh"
set -u

say "$TEST — offline start, back to the phone"
reset

say "Phone out of reach; offline start on the watch"
sim phone away
start=$(now)
offline_start "$start"

say "Two watch loop cycles"
wait_for watch "$start" 'cycle computed,' 720 2

say "Phone back; End on the watch"
sim phone back
sleep 10
watch_main
end=$(now)
ui watch tap End
wait_for watch "$end" 'loan closed' 180
wait_for phone "$end" 'temp cancelled' 120

say "Checks"
expect watch "$start" 'offline start confirmed as loan' "offline start confirmed"
expect watch "$start" 'offline loan [0-9]+ active' "watch active on its own"
expect phone "$start" 'adopting the loan the watch started' "phone adopted the loan"
# Either the phone's window ends at the watch's takeover, or, when the returning phone read the pod
# before it heard from the watch, the watch's window starts at that later reading.
expect phone "$start" 'until the watch took over|window starts at this phone.s later reading' "phone's own window ended at the watch's takeover, or at the phone's own later reading"
expect_clean phone "$end" 'hand-back check:' "hand-back's check"
expect phone "$end" 'temp cancelled' "watch's temp ended"
verdict
