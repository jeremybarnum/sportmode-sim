#!/bin/sh
# T31 — The watch's own session count saved late. Each pod session moves the pod's count, and the
# watch's copy of it is saved with the pump state, a moment later. Killed in between, the watch
# relaunches with a count behind the pod's. Its next session meets a resync of its own making: the
# pod driver keeps the last count the pod accepted from it, saved at once, and must take the resync
# as its own and carry on. Read as another controller's, it stops and the watch stops looping.
# Simulated: the watch app is quit after a cycle and its saved count rolled back by 3 before it
# relaunches. Needs a pod simulator that answers a stale session count with a resync.
TEST=T31
. "$(dirname "$0")/lib.sh"
set -u

pump_state_file() {
	local c
	c=$(xcrun simctl get_app_container "$WATCH_SIM_ID" "$("$SIM" bundle watch)" data) || return 1
	echo "$c/Documents/PumpManagerState.plist"
}
COUNT=state.podState.bleMessageTransportState.eapSeq

# The pod driver's own lines go to the watch app's watch.log, beside the harness's g7watch.log.
driver_lines() { # since regex
	awk -v t="$(date +%F) $1" '($1 " " $2) >= t' "$(dirname "$("$SIM" applog watch)")/watch.log" | grep -E "$2" | cut -c12-260
}
driver_wait() { # since regex seconds
	local _end=$(($(date +%s) + $3))
	while [ -z "$(driver_lines "$1" "$2")" ]; do
		[ "$(date +%s)" -ge "$_end" ] && abort "the watch's pod driver did not log /$2/ within $3 s"
		sleep 2
	done
	driver_lines "$1" "$2" | head -1
}

say "$TEST — the watch's session count saved late"
reset

say "Start on the watch, one loop cycle"
start=$(now)
start_loan "$start"
wait_for watch "$start" 'cycle computed,' 400

say "Quit the watch app; roll its saved session count back by 3"
f=$(pump_state_file) || abort "no watch pump state file"
q=$(now)
sim quit watch
sleep 3
seq=$(plutil -extract "$COUNT" raw "$f") || abort "no session count in the watch's pump state"
plutil -replace "$COUNT" -integer $((seq - 3)) "$f" || abort "could not roll the count back"
say "saved count $seq now reads $((seq - 3))"

say "Relaunch: the first session meets the pod's count, the watch's own"
sim launch watch
wait_for watch "$q" 'resumed loan' 60
r=$(driver_wait "$q" 'sqn-resync' 400 | cut -c1-8)
wait_for watch "$r" 'cycle computed,' 400

say "End on the watch"
watch_main
end=$(now)
ui watch tap End
wait_for watch "$end" 'loan closed' 180

say "Checks"
l=$(driver_lines "$q" 'sqn-resync' | head -1)
case "$l" in
*"own sessions, saved late"*) pass "the driver took the resync as the watch's own" "$l" ;;
*) fail "the driver took the resync as the watch's own" "${l:-no resync line in the watch driver log}" ;;
esac
l=$(driver_lines "$q" 'another controller has used this pod')
[ -z "$l" ] && pass "the driver reported no other controller" "no such driver line" || fail "the driver reported no other controller" "$l"
expect_none watch "$q" 'found another controller' "the watch heard of no other controller"
expect watch "$r" 'cycle computed,' "the watch kept looping after the resync"
expect watch "$end" 'loan closed' "the loan ended normally"
verdict
