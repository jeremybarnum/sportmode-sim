#!/bin/sh
# T23 — A watch bolus that reaches the phone after it has handed the pod over is refused: the phone
# logs "Refusing watch bolus while the pod is on loan", posts "Bolus Not Delivered", and nothing is
# given; the loan goes on. (1) The bolus tapped in the takeover window, after the phone's grant and
# before the watch is active: the watch's radio is held out of range to keep the window open (the
# phone must reach the pod itself to grant). (2) The bolus sent right after Start on a link 8 s slow
# each way, so it arrives after the grant. The watch's bolus is a live message and the phone drops
# one over 30 s old, so a bolus queued while the phone was away cannot reach it later.
TEST=T23
. "$(dirname "$0")/lib.sh"
set -u

# The phone's system log since a time: the line containing a text, or nothing.
oslog() { # since text
	xcrun simctl spawn "$PHONE_SIM_ID" log show --start "$(date +%F) $1" --style compact \
		--predicate "process == \"Loop\" AND eventMessage CONTAINS \"$2\"" 2>/dev/null | grep -v '^Timestamp\|^ *Ty' | tail -1
}
# The pod's delivered total, from the pod simulator.
pod_delivered() {
	curl -s -m 3 "localhost$("$SIM" podapi)/status" | python3 -c 'import json, sys; print(json.load(sys.stdin)["delivered"])'
}
# End, again after any automatic bolus under way (an End waits for it), until the hand-back closes.
end_loan() { # case
	local i t
	for i in 1 2 3 4; do
		watch_main
		t=$(now)
		ui watch tap End
		logged_within watch "$t" 'HAND-BACK requested' 15 && { wait_for watch "$t" 'CLOSED — ' 120 >/dev/null; wait_for phone "$t" 'reconcile\[AUTHORITATIVE\]' 60 >/dev/null; echo "$t"; return 0; }
		say "the End was not taken or a bolus is under way; again in 30 s" >&2
		sleep 30
	done
	abort "($1) the End did not go through"
}
# A refused bolus: the system log line, the notification, and the pod's total not moved by it.
refused() { # case since delivered-before
	local line note after
	line=$(oslog "$2" "Refusing watch bolus while the pod is on loan")
	[ -n "$line" ] && pass "($1) the phone refused the watch's bolus" "$line" || fail "($1) the phone refused the watch's bolus" "no refusal in the phone's system log"
	note=$(python3 "$root/tests/notifications.py" "$PHONE_SIM_ID" --since "$2" delivered | grep "	Bolus Not Delivered	" | head -1)
	[ -n "$note" ] && pass "($1) the phone posted \"Bolus Not Delivered\"" "$note" || fail "($1) the phone posted \"Bolus Not Delivered\"" "no such notification since $2"
	after=$(pod_delivered)
	if awk -v a="$after" -v b="$3" 'BEGIN { exit !(a - b < 0.5) }'; then
		pass "($1) nothing given for it" "pod total $3 → $after U (basal only)"
	else
		fail "($1) nothing given for it" "pod total $3 → $after U"
	fi
	expect_none phone "$2" 'MANUAL BOLUS|enacting bolus' "($1) the phone did not enact it"
}

say "$TEST — a watch bolus reaching the phone after the handover"
# Glucose near the target, so the watch has no automatic bolus under way when the test ends a loan.
"$SIM" glucose 110 >/dev/null
reset

say "(1) The watch's radio out of range; Start; after the phone's grant, a 1 U watch bolus"
sim watch away
s1=$(tap_start)
wait_for phone "$s1" 'GRANT — releasing pod BLE' 60
d1=$(pod_delivered)
b1=$(now)
watch_bolus_send 1
sleep 10
sim watch back
wait_for watch "$s1" 'ACTIVE — epoch' 90
expect_none watch "$s1" 'TAKEOVER ABORTED|TAKEOVER FAILED' "(1) the takeover went through"
refused 1 "$b1" "$d1"

say "(1) End; the loan hands back cleanly"
e1=$(end_loan 1)
expect_clean phone "$e1" 'reconcile\[AUTHORITATIVE\]' "(1) the hand-back's check"

say "(2) Link 8 s slow each way; Start, then a 1 U watch bolus at once"
sim link slow 8
watch_start_shown
d2=$(pod_delivered)
s2=$(now)
ui watch tap "Start Sport Mode"
watch_bolus_send 1
b2=$s2
wait_for phone "$s2" 'GRANT — releasing pod BLE' 60
logged_within watch "$s2" 'ACTIVE — epoch' 90 || true
sleep 20
sim link normal
wait_for watch "$s2" 'ACTIVE — epoch' 90
grant=$(lines phone "$s2" 'GRANT — releasing pod BLE' | head -1 | cut -c1-12)
ref=$(oslog "$s2" "Refusing watch bolus while the pod is on loan" | awk '{print $2}' | cut -c1-12)
say "grant $grant, refusal ${ref:-none}"
refused 2 "$b2" "$d2"

say "(2) End; the loan hands back cleanly"
e2=$(end_loan 2)
expect_clean phone "$e2" 'reconcile\[AUTHORITATIVE\]' "(2) the hand-back's check"
verdict
