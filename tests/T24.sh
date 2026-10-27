#!/bin/sh
# T24 — A command whose answer is lost, then a start without the phone. The pod holds the phone's
# 0.5 U bolus 15 s before acting on it, and the phone leaves the pod's reach during the hold: the pod
# gives the bolus, its answer never reaches the phone, and the phone's pod driver keeps the command
# as unconfirmed. The watch starts without the phone. When the phone is back it stands aside, its
# driver keeps the pod, and the phone reads the pod at once: the read finds the pod's session count
# ahead, the sign another device has run it, so the driver drops the command with nothing booked and
# lets go of the pod. The phone's own
# insulin check up to the watch's takeover books the bolus, and the hand-back's check is clean.
# Needs a pod simulator that answers a stale session count with a resync, as a pod does
# (LoopKit/pod#25; POD_SIM in the rig's .sims).
TEST=T24
. "$(dirname "$0")/lib.sh"
set -u

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
wait_for watch "$start" 'cycle computed,' 720 2

say "Phone back: it stands aside and reads the pod, which resyncs"
back=$(now)
sim phone back
wait_for phone "$back" 'adopting the loan the watch started|standing aside for a loan the watch started' 180
dropped=$(oslog_wait "$back" "dropped, nothing booked" 60)
released=$(oslog_wait "$back" "releaseConnection" 30)

say "End on the watch"
sleep 10
watch_main
end=$(now)
ui watch tap End
wait_for watch "$end" 'loan closed' 180
wait_for phone "$end" 'hand-back check:' 120

say "Checks"
held=$(pod_lines "$b" 'holding command with sequence' | head -1)
[ -n "$held" ] && pass "the pod held the phone's command" "$held" || fail "the pod held the phone's command" "no hold in the pod's log since $b"
expect watch "$start" 'offline start confirmed as loan' "offline start confirmed"
sync=$(pod_lines "$back" 'sending a synchronization failure' | head -1)
[ -n "$sync" ] && pass "the pod answered the phone's stale session count" "$sync" \
	|| fail "the pod answered the phone's stale session count" "no resync since $back: does this rig's pod simulator resync (LoopKit/pod#25, POD_SIM)?"
[ -n "$dropped" ] && pass "the phone's driver dropped the unconfirmed command, nothing booked" "$dropped" \
	|| fail "the phone's driver dropped the unconfirmed command, nothing booked" "no such line in the phone's system log since $back"
refused=$(oslog "$back" "[release] refused" | head -1)
say "before that, a refusal to let go: ${refused:-none (the resync came first)}" | cut -c1-220
[ -n "$refused" ] && expect phone "$back" 'reading the pod to settle it' "the phone read the pod at once to settle the command"
[ -n "$released" ] && pass "the phone's driver let go of the pod" "$released" \
	|| fail "the phone's driver let go of the pod" "no release in the phone's system log since $back"
expect phone "$back" 'adopting the loan the watch started' "the phone adopted the loan"
expect_residual phone "$back" 'until the watch took over' 0.30 0.70 "the phone's own check books the bolus up to the watch's takeover"
expect_clean phone "$end" 'hand-back check:' "hand-back's check"
expect_none phone "$b" 'Overstated' "no false overstated warning"
verdict
