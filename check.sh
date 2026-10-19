#!/bin/sh
# The pass and fail lines of a bench test (SPORT_MODE_BENCH_TESTS.md), read from both apps' logs
# since a time: check.sh T1 14:40:00. Prints the lines each side's test names, in order; the
# reading of them is the test's own "Pass" section.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
t=${1:?test, e.g. T1}
since=${2:?HH:MM:SS}
p() { "$here/sim.sh" since phone "$since" "$1"; }
w() { "$here/sim.sh" since watch "$since" "$1"; }
case "$t" in
T1 | T2)
	echo "== phone"; p 'odometer\] \(own\).*until the watch|reconcile\[|temp cancelled|reclaim VERIFIED|STILL CONNECTED|Unexplained'
	echo "== watch"; w 'ACTIVE —|odometer\] \(own\)|BOOKED|hand-back|HAND-BACK|ack RECEIVED|CLOSED —|drain GIVING UP|staying RELEASED|CYCLE VERDICT' ;;
T3 | T5)
	echo "== phone"; p 'take-back|revoke|reconcile\[|temp cancelled|REFUSED|Couldn'"'"'t Reach'
	echo "== watch"; w 'revoke|REVOKED|CLOSED|stood aside|CYCLE VERDICT' ;;
T4 | T7 | T19)
	echo "== phone"; p 'reconcile\[|estimate BOOKED|estimate RETIRED|over the last|odometer\] \(own\)|RETRO-ACK|no answer from the watch|revived watch|keeps the pod|temp cancelled|Overstated|Records Recovered|Insulin Estimated'
	echo "== watch"; w 'RESUMED|odometer\] \(own\)|BOOKED|dosemath|enacting|revoke|REVOKED|statusReport sent|SEIZE|seized loan|CYCLE VERDICT|Checking with' ;;
T6 | T10 | T13 | T14)
	echo "== phone"; p 'seize|RETRO-ACK|odometer\] \(own\).*until|reconcile\[|temp cancelled|GRANT —|loan ABANDONED|dead-man'
	echo "== watch"; w 'REQUEST|offline start|SEIZE|seized loan|GRANT received|ACTIVE —|TAKEOVER FAILED|REJECTED|reachable after all|phone went out of reach|hand-back' ;;
T8 | T16 | T17)
	echo "== phone"; p 'asking the watch|did NOT answer|take-back|reconcile\[|temp cancelled|status report from a CLOSED|revoke|Not Responding'
	echo "== watch"; w 'RESUMED|odometer\] \(own\)|BOOKED|dosemath|enacting|statusReport sent|RX revoke|REVOKED|stood aside|CYCLE VERDICT' ;;
T11)
	echo "== phone"; p 'carb DELETE'
	echo "== watch"; w 'carb|DELETE' ;;
T18)
	echo "== phone"; p 'offer RX|commit done|reclaim VERIFIED|temp cancelled'
	echo "== watch"; w 'hand-back offer|HAND-BACK|ack RECEIVED|CLOSED —|continues' ;;
*) echo "no lines defined for $t" >&2; exit 2 ;;
esac
