#!/bin/sh
# Not a bench test: tries to reproduce the watch crash of 2026-10-20 02:38 (OmniPumpManager.store(doses:)
# with no delegate) — the phone takes the pod back from a running loan, and Start comes right after
# the watch closes it. Repeats; reports any new WatchApp crash report.
TEST=repro
. "$(dirname "$0")/lib.sh"
set -u
before=$(ls ~/Library/Logs/DiagnosticReports/ | grep -c '^WatchApp')
for i in 1 2 3; do
	say "round $i"
	reset
	s=$(now); start_loan "$s"
	# A loan with doses behind it, as the one that crashed: a reading, and the cycle it starts.
	r=$(now); wait_reading "$r" 400
	wait_for watch "$r" 'CYCLE VERDICT computed=ok' 120
	sleep 5
	tb=$(now)
	take_back
	wait_for watch "$tb" 'CLOSED — ' 60
	g=$(now)
	ui watch wait 10 "Start Sport Mode"
	ui watch tap "Start Sport Mode"
	sleep 15
	if [ "$(ls ~/Library/Logs/DiagnosticReports/ | grep -c '^WatchApp')" -gt "$before" ]; then
		say "WATCH CRASHED in round $i: $(ls -t ~/Library/Logs/DiagnosticReports/ | grep '^WatchApp' | head -1)"
		failed=1; verdict
	fi
	expect watch "$g" 'GRANT received' "round $i: the Start after the take-back was granted"
done
verdict
