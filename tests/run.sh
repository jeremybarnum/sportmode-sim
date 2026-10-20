#!/bin/sh
# Runs bench test scripts one after another, unattended: tests/run.sh T1 T3 (no argument: all of
# them). Each test's output goes to build/results/<run>/<test>.log; a summary is printed at the end
# and kept in summary.txt. The simulators and both apps must be running (sim.sh start, launch).
set -u
here=$(cd "$(dirname "$0")" && pwd)
dir=$here/../build/results/$(date +%Y%m%d-%H%M%S)
mkdir -p "$dir"
[ $# -gt 0 ] || set -- $(ls "$here" | sed -n 's/^\(T[0-9]*\)\.sh$/\1/p' | sort -t T -k 2 -n)
for t in "$@"; do
	printf '%s  %s ...\n' "$(date +%T)" "$t"
	if "$here/$t.sh" >"$dir/$t.log" 2>&1; then r=PASS; else r=FAIL; fi
	printf '%s  %s %s\n' "$(date +%T)" "$t" "$r" | tee -a "$dir/summary.txt"
done
echo "logs: $dir"
grep -q FAIL "$dir/summary.txt" && exit 1 || exit 0
