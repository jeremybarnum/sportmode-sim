#!/bin/sh
# P1 — An ordinary loan on the production line, ended on the watch. The watch takes the pod (its saved
# handle or the scan), reads the sensor through the Dexcom app's link and loops, then hands the pod
# back; the phone's audit over the watch's window is clean and the watch's temp is cancelled.
TEST=P1
. "$(dirname "$0")/lib.sh"
set -u

say "$TEST — ordinary loan, ended on the watch"
reset

say "Start on the watch"
start=$(now)
start_loan "$start"

say "A reading on the watch through the Dexcom app's link, and a loop cycle after it (up to 6 minutes)"
wait_for watch "$start" 'INGEST src=direct-G7' 360
read_at=$(lines watch "$start" 'INGEST src=direct-G7' | head -1 | cut -c1-12)
wait_for watch "$read_at" 'cycle OK' 120

say "End on the watch"
watch_main
end=$(now)
ui watch tap End
wait_for watch "$end" 'CLOSED — ' 120
wait_for phone "$end" 'R33 temp cancel' 120

say "Checks"
expect phone "$start" 'GRANT — releasing pod BLE' "phone granted and released the pod"
expect watch "$start" 'takeover ladder start — lease \+(29[0-9]|300)s' "takeover lease of 5 minutes"
expect watch "$start" 'ACTIVE — epoch' "watch active"
check_keepalive "$start"
expect watch "$start" 'connection-event CONNECT' "the watch heard the Dexcom app's link come up"
expect watch "$start" 'INGEST src=direct-G7' "the watch read the sensor through that link"
expect watch "$read_at" 'cycle OK' "the watch looped on its reading"
expect watch "$end" 'HAND-BACK requested' "hand-back started"
expect watch "$end" 'ack RECEIVED' "phone acknowledged the hand-back"
expect phone "$end" 'offer RX .*released=final' "phone took the final offer"
expect phone "$end" 'reclaim VERIFIED' "phone verified the pod"
expect_clean phone "$end" 'reconcile\[AUTHORITATIVE\]' "phone's audit over the watch's window"
expect phone "$end" 'R33 temp cancelled' "watch's temp cancelled"
expect_none phone "$start" 'force reclaim|Watch Session Unverified' "no forced or unverified ending"
verdict
