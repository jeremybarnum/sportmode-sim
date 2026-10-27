#!/bin/sh
# Not a bench test: tries to reproduce the watch crash of 2026-10-20 02:38 (OmniPumpManager.store(doses:)
# with no delegate) — the phone takes the pod back from a running loan, and Start comes right after
# the watch closes it. Repeats; reports any new WatchApp crash report.
TEST=repro
. "$(dirname "$0")/lib.sh"
set -u
before=$(ls ~/Library/Logs/DiagnosticReports/ | grep -c '^WatchApp')
for i in 1 2 3 4; do
	say "round $i"
	reset
	s=$(now); start_loan "$s"
	# As before the crash: the watch app relaunched during the loan, and resumed it.
	q=$(now); sim quit watch; sleep 3; sim launch watch
	wait_for watch "$q" 'resumed loan' 60
	sleep ${REPRO_WAIT:-70}
	tb=$(now)
	take_back
	wait_for watch "$tb" 'loan closed' 60
	g=$(now)
	ui watch wait 10 "Start Sport Mode"
	ui watch tap "Start Sport Mode"
	sleep 15
	if [ "$(ls ~/Library/Logs/DiagnosticReports/ | grep -c '^WatchApp')" -gt "$before" ]; then
		say "WATCH CRASHED in round $i: $(ls -t ~/Library/Logs/DiagnosticReports/ | grep '^WatchApp' | head -1)"
		failed=1; verdict
	fi
	expect watch "$g" 'grant received' "round $i: the Start after the take-back was granted"
done
verdict
