#!/bin/sh
# T27 — No program crosses a Start. (a) An ordinary Start: the watch cancels any temp at the takeover
# and sends the pod nothing else until the next sensor reading starts its first cycle. (b) An offline
# Start while the phone runs a low temp: the watch's cancel stops that temp on the pod, and its first
# cycle, at the next reading, sets its own.
TEST=T27
. "$(dirname "$0")/lib.sh"
set -u

# hold <mg/dL> <readings>: the sensor at a value for that many readings.
hold() {
	local i t
	sim glucose "$1"
	for i in $(seq 1 "$2"); do t=$(now); wait_reading "$t" 330; done
}

say "$TEST — no program crosses a Start"
reset

say "(a) An ordinary Start, glucose steady"
hold 120 1
a=$(now)
start_loan "$a"
wait_for watch "$a" 'temp basal cancelled at takeover' 60
took=$(now)
wait_reading "$took" 330
wait_for watch "$took" 'cycle computed,' 120
first=$(lines watch "$a" 'cycle computed,' | head -1 | cut -c1-12)
watch_main
ea=$(now)
ui watch tap End
wait_for watch "$ea" 'loan closed' 180

say "(b) Glucose low until the phone sets a low temp; phone away; offline Start"
low=$(now)
hold 70 2
sim phone away
sleep 5
b=$(now)
offline_start "$b"
wait_for watch "$b" 'temp basal cancelled at takeover' 60
tb=$(now)
wait_reading "$tb" 330
wait_for watch "$tb" 'cycle computed,' 120
say "Phone back; End"
sim phone back
sleep 10
watch_main
eb=$(now)
ui watch tap End
wait_for watch "$eb" 'loan closed' 180
wait_for phone "$eb" 'temp cancelled' 120
sim glucose 120

say "Checks"
expect watch "$a" 'loan [0-9]+ active' "(a) the watch took the pod"
expect watch "$a" 'temp basal cancelled at takeover' "(a) the cancel at the takeover"
expect_none_between watch "$a" "$took" '\[dose\] enacting (automatic bolus|temp [0-9.]+ U/hr for [1-9])' "(a) no dose at the takeover but the cancel"
expect_between watch "$took" "$ea" '\[dose\] enacting|no command needed' "(a) the first cycle decides at the next reading"
[ -n "$first" ] && [ "$first" \> "$took" ] && pass "(a) the first cycle came after the takeover's cancel" "cancel by $took, first cycle $first" || fail "(a) the first cycle came after the takeover's cancel" "cancel by $took, first cycle ${first:-never}"
l=$(pod_lines "$low" 'PROGRAM_INSULIN|TEMP_BASAL|SET_INSULIN' | head -1)
[ -n "$l" ] && pass "(b) the phone programmed the pod while glucose was low" "$l" || fail "(b) the phone programmed the pod while glucose was low" "no program command after $low"
expect watch "$b" 'offline loan [0-9]+ active' "(b) the watch took the pod offline"
expect watch "$b" 'temp basal cancelled at takeover' "(b) the cancel at the offline takeover"
l=$(pod_lines "$b" 'StopDelivery' | head -1)
[ -n "$l" ] && pass "(b) the pod received the cancel" "$l" || fail "(b) the pod received the cancel" "no StopDelivery after $b"
expect_none_between watch "$b" "$tb" '\[dose\] enacting (automatic bolus|temp [0-9.]+ U/hr for [1-9])' "(b) no dose at the offline takeover but the cancel"
expect_between watch "$tb" "$eb" '\[dose\] enacting temp 0\.00' "(b) the watch's first cycle set its own low temp"
verdict
