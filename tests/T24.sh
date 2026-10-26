#!/bin/sh
# T24 — A command whose answer is lost, then a start without the phone. The pod holds the phone's
# 0.5 U bolus 15 s before acting on it, and the phone leaves the pod's reach during the hold: the pod
# gives the bolus, its answer never reaches the phone, and the phone's pod driver keeps the command
# as unconfirmed. The watch starts without the phone. When the phone is back it stands aside; its
# first exchange with the pod finds the pod's session count ahead, the sign another device has run
# it, so its driver drops the command with nothing booked and lets go of the pod. The phone's own
# insulin check up to the watch's takeover books the bolus, and the hand-back's check is clean.
# Needs a pod simulator that answers a stale session count with a resync, as a pod does
# (LoopKit/pod#25; POD_SIM in the rig's .sims).
TEST=T24
. "$(dirname "$0")/lib.sh"
set -u

# The phone's system log since a time: the lines containing a text. The pod driver's own lines go
# there, not to the app's log file.
oslog() { # since text
	xcrun simctl spawn "$PHONE_SIM_ID" log show --start "$(date +%F) $1" --style compact \
		--predicate "process == \"Loop\" AND eventMessage CONTAINS \"$2\"" 2>/dev/null | grep -v '^Timestamp\|^ *Ty'
}
# Wait for such a line; prints it, or nothing after the seconds given.
oslog_wait() { # since text seconds
	local _end _l
	_end=$(($(date +%s) + $3))
	while :; do
		_l=$(oslog "$1" "$2" | tail -1)
		[ -n "$_l" ] && { echo "$_l"; return 0; }
		[ "$(date +%s)" -ge "$_end" ] && return 0
		sleep 5
	done
}

say "$TEST — a lost answer, a start without the phone, the phone back"
# Glucose near the target, so no automatic bolus is under way when the watch ends the loan.
"$SIM" glucose 110 >/dev/null
reset

say "The pod holds the next command 15 s; a 0.5 U bolus on the phone; the phone out of reach during the hold"
b=$(now)
sim pod slow 15
phone_bolus 0.5
sim phone away
say "The pod gives it: 15 s held, then 0.05 U every 2 s"
sleep 45

say "Offline start on the watch"
start=$(now)
offline_start "$start"

say "Two watch loop cycles"
wait_for watch "$start" 'CYCLE VERDICT computed=ok' 720 2

say "Phone back: it stands aside; its first exchange with the pod resyncs"
back=$(now)
sim phone back
wait_for phone "$back" 'RETRO-ACK|YIELDING to an inferred loan' 180
dropped=$(oslog_wait "$back" "dropped, nothing booked" 300)
released=$(oslog_wait "$back" "releaseConnection" 120)

say "End on the watch"
sleep 10
watch_main
end=$(now)
ui watch tap End
wait_for watch "$end" 'CLOSED — ' 180
wait_for phone "$end" 'reconcile\[AUTHORITATIVE\]' 120

say "Checks"
held=$(pod_lines "$b" 'holding command with sequence' | head -1)
[ -n "$held" ] && pass "the pod held the phone's command" "$held" || fail "the pod held the phone's command" "no hold in the pod's log since $b"
expect watch "$start" 'SEIZE confirmed' "offline start confirmed"
sync=$(pod_lines "$back" 'sending a synchronization failure' | head -1)
[ -n "$sync" ] && pass "the pod answered the phone's stale session count" "$sync" \
	|| fail "the pod answered the phone's stale session count" "no resync since $back: does this rig's pod simulator resync (LoopKit/pod#25, POD_SIM)?"
[ -n "$dropped" ] && pass "the phone's driver dropped the unconfirmed command, nothing booked" "$dropped" \
	|| fail "the phone's driver dropped the unconfirmed command, nothing booked" "no such line in the phone's system log since $back"
refused=$(oslog "$back" "[release] refused" | head -1)
say "before that, a refusal to let go: ${refused:-none (the resync came first)}" | cut -c1-220
[ -n "$released" ] && pass "the phone's driver let go of the pod" "$released" \
	|| fail "the phone's driver let go of the pod" "no release in the phone's system log since $back"
expect phone "$back" 'RETRO-ACK' "the phone adopted the loan"
expect_residual phone "$back" 'until the watch took over' 0.30 0.70 "the phone's own check books the bolus up to the watch's takeover"
expect_clean phone "$end" 'reconcile\[AUTHORITATIVE\]' "hand-back's check"
expect_none phone "$b" 'Overstated' "no false overstated warning"
verdict
