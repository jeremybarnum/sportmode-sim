#!/bin/sh
# Runs bench test scripts one after another, unattended: tests/run.sh T1 T3 (no argument: all of
# them; fast (or quick), safety, validation: the tiers in TESTS.md). Each test's output goes to build/results/<run>/<test>.log,
# and its stretch of the apps' and simulators' logs to <run>/<test>/; a summary
# is printed at the end and kept in summary.txt. The simulators and both apps must be running (sim.sh start, launch).
set -u
here=$(cd "$(dirname "$0")" && pwd)
# One run at a time in a slot: two share one tap driver, one mux and one Simulator pair, and corrupt
# each other. Rigs in different slots (SLOT=<n> in their .sims-<rig>) run side by side. The lock names
# the run's process; a lock whose process is gone is stale and taken over.
SLOT=$(sed -n 's/^SLOT=//p' "$here/../.sims${RIG:+-$RIG}" 2>/dev/null | tail -1)
lock=$here/../build/run/run.lock; [ "${SLOT:-0}" = 0 ] || lock=$here/../build/run/run-slot$SLOT.lock
mkdir -p "$(dirname "$lock")"
if [ -f "$lock" ] && kill -0 "$(cat "$lock" 2>/dev/null)" 2>/dev/null; then
	echo "another run is active (pid $(cat "$lock")): wait for it, or stop it" >&2; exit 2
fi
echo $$ >"$lock"
# The tap drivers are two test runners that stay attached to the apps; a run ends them with itself.
trap 'rm -f "$lock"; "$here/../ui.sh" stop phone 2>/dev/null; "$here/../ui.sh" stop watch 2>/dev/null' EXIT
# Tests kept elsewhere: TESTS_DIR=<their folder>, with their RIG.
tests=${TESTS_DIR:-$here}
dir=$here/../build/results/${RIG:+$RIG-}$(date +%Y%m%d-%H%M%S)
mkdir -p "$dir"
[ $# -gt 0 ] || set -- $(ls "$tests" | sed -n 's/^\([A-Z][A-Z0-9]*[a-z]*\)\.sh$/\1/p' | sort -k 1.2 -n)
# quick: a check between review rounds, the full run stays the gate. T1 an ordinary loan (takeover,
# records, hand-back, audit), T5 a take-back (settle, verification, stop), T13 an offline start
# whose take stalls (escalation). Tests named after it run too: quick T22.
# The tiers are in TESTS.md: fast (quick), safety, validation.
case "${1:-}" in
quick|fast) shift; set -- T1 T5 T13 "$@" ;;
safety) shift; set -- T4 T7 T16 T17 T19 T22 T23 "$@" ;;
validation) shift; set -- T3 T6 T8 T10 T11 T18 T25 T26 "$@" ;;
esac
# Each test's own stretch of the apps' and the simulators' logs is kept with its result, in <test>/: the
# apps' logs roll over and a start replaces the simulators', so a failure's evidence would not last.
sims=$here/../build/run${RIG:+-$RIG}
size() { wc -c <"$sims/$1.log" 2>/dev/null | tr -d ' ' || echo 0; }
keep_logs() { # test since offsets(pod g7 mux)
	local t=$1 since=$2 o
	mkdir -p "$dir/$t"
	for side in phone watch; do "$here/../sim.sh" since "$side" "$since" >"$dir/$t/$side.log" 2>/dev/null || true; done
	shift 2
	for sim in pod g7 mux; do
		# A log replaced during the test (a restart) is kept whole.
		o=$1; shift
		[ "$(size $sim)" -ge "$o" ] 2>/dev/null || o=0
		tail -c +$((o + 1)) "$sims/$sim.log" >"$dir/$t/$sim.log" 2>/dev/null || true
	done
}
for t in "$@"; do
	since=$(date +%T); offsets="$(size pod) $(size g7) $(size mux)"
	printf '%s  %s ...\n' "$since" "$t"
	if "$tests/$t.sh" >"$dir/$t.log" 2>&1; then r=PASS; else r=FAIL; fi
	keep_logs "$t" "$since" $offsets
	printf '%s  %s %s\n' "$(date +%T)" "$t" "$r" | tee -a "$dir/summary.txt"
done
echo "logs: $dir"
grep -q FAIL "$dir/summary.txt" && exit 1 || exit 0
