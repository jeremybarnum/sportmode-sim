#!/bin/sh
# Reproduction, not a bench test: a take-back after the watch ended a temp before its planned end.
# Seen 2026-10-21 in a dry run: the phone's salvage of the watch's unacknowledged records wrote that
# temp from its planned end back to the take-back (a negative duration); Core Data refused it, and
# every later save on the phone failed with it, so the watch's hand-back never closed.
# Steps: glucose held low so the watch sets a low temp; glucose raised until the watch ends that temp
# (a cancel back to the schedule, or another temp); take back on the phone; then the phone's writes
# are watched, the phone app relaunched, and watched again. Needs a phone with little insulin on board,
# or the watch never leaves its low temp. INTERIM=1 first has an End fail on a slow link, so the phone
# has written and acknowledged one hand-back offer; LATE_TEMP=1 (with INTERIM=1) holds glucose at 115
# until then, so the temp comes after that offer, as in the dry run. RELAUNCH=1: instead of raising
# glucose, the watch app is quit and relaunched while the temp runs, as happened in the dry run: there
# the resumed watch journaled a cancel from its first pod read though the pod was still on the temp.
TEST=repro-salvage
. "$(dirname "$0")/lib.sh"
set -u

# hold <mg/dL> <readings>: the sensor at a value for that many readings.
hold() {
	local i t
	sim glucose "$1"
	for i in $(seq 1 "$2"); do t=$(now); wait_for watch "$t" 'INGEST src=direct-G7' 330 >/dev/null; done
}

say "$TEST — a take-back after the watch ended a temp early"
reset

bg=75; [ "${LATE_TEMP:-0}" = 1 ] && bg=115
say "Glucose held at $bg; Start"
hold "$bg" 2
start=$(now)
start_loan "$start"
if [ "${INTERIM:-0}" = 1 ]; then
	say "End on a link 6 s slow each way: the watch gives up after 10 s, the phone answers late"
	sim link slow 6
	watch_main
	te=$(now)
	ui watch tap End
	wait_for watch "$te" 'HAND-BACK not possible' 60
	wait_for phone "$te" 'write DONE' 60
	sim link normal
fi
if [ "${LATE_TEMP:-0}" = 1 ]; then
	say "Glucose down 8 a reading until the watch sets a low temp"
	tt=$(now)
	for v in 107 99 91 83 75 75 75; do
		sim glucose "$v"
		t=$(now)
		wait_for watch "$t" 'INGEST src=direct-G7' 330 >/dev/null
		sleep 15
		[ -n "$(lines watch "$tt" 'tempBasal JOURNALED.*0\.00 U/hr')" ] && break
	done
	wait_for watch "$tt" 'tempBasal JOURNALED' 60
else
	wait_for watch "$start" 'tempBasal JOURNALED' 600
fi
lt=$(now)

ended=
if [ "${RELAUNCH:-0}" = 1 ]; then
	say "Watch app quit and relaunched while the temp runs"
	sim quit watch
	sleep 3
	rw=$(now)
	sim launch watch
	wait_for watch "$rw" 'RESUME: pump manager built|RESUMED' 120
	logged_within watch "$rw" 'cancel JOURNALED|tempBasal JOURNALED' 120 || true
	ended=$(lines watch "$rw" 'cancel JOURNALED|tempBasal JOURNALED' | head -1)
	lines watch "$rw" 'RESUME|RESUMED|no command needed|enacting' | head -6
	[ -n "$ended" ] || ended="nothing journaled after the relaunch"
fi
[ -n "$ended" ] || say "Glucose up to the target, a reading at a time, until the watch ends that temp"
[ -n "$ended" ] || for v in 90 105 110 110 110 120 130 110 110 110; do
	sim glucose "$v"
	t=$(now)
	wait_for watch "$t" 'INGEST src=direct-G7' 330 >/dev/null
	sleep 15
	ended=$(lines watch "$lt" 'cancel JOURNALED|tempBasal JOURNALED' | head -1)
	[ -n "$ended" ] && break
done
[ -n "$ended" ] || abort "the watch did not end its temp"
say "ended: $ended"

say "Take the pod back on the phone"
tb=$(now)
take_back
wait_for phone "$tb" 'reclaim VERIFIED' 60
sleep 45

say "Relaunch the phone app; watch its writes again"
rl=$(now)
"$SIM" launch phone >/dev/null
logged_within watch "$rl" 'CLOSED — ' 120 || true

say "Evidence"
lines phone "$tb" 'SALVAGE' | head -3
lines phone "$tb" 'write (START|DONE|FAILED)' | cut -c1-200 | head -8
f=$("$SIM" applog phone)
grep -A16 "write FAILED" "$f" | grep -E "write FAILED|date =|createdAt =|duration =|doseType =|value =" | head -12
echo "failed writes before the relaunch: $(lines phone "$tb" 'FAILED: coreDataError' | awk -v r="$rl" '$1 < r' | wc -l | tr -d ' ')"
echo "failed writes after the relaunch:  $(lines phone "$rl" 'FAILED: coreDataError' | wc -l | tr -d ' ')"
lines watch "$tb" 'CLOSED — ' | head -1

say "Checks"
expect_none phone "$tb" 'write FAILED' "the phone's writes after the take-back succeed"
expect watch "$tb" 'CLOSED — ' "the watch's hand-back closed"
verdict
