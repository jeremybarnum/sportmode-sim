#!/bin/sh
# T29 — A connect request the system loses without telling the watch (seen once, 2026-10-05, after an
# install). The watch's own readings stop, and nothing but the sensor wakes it to notice (the sensor is
# the heartbeat, as on the phone). Relaunching the watch app repairs it: launch runs the acquisition
# check, which places a new request.
TEST=T29
. "$(dirname "$0")/lib.sh"
set -u

# The watch's system log since a time: G7's acquisition lines go there.
watch_oslog() { # since text
	xcrun simctl spawn "$WATCH_SIM_ID" log show --start "$(date +%F) $1" --style compact \
		--predicate "subsystem == \"org.loopkit.G7SensorKit\" AND eventMessage CONTAINS \"$2\"" 2>/dev/null |
		grep -v '^Timestamp\|^ *Ty'
}

say "$TEST — a lost connect request, repaired by relaunching the watch app"
reset

say "The watch reads the sensor itself, then places its next request"
t=$(now)
wait_for watch "$t" 'G7 reading' $(( $(sc 900) + 60 )) >/dev/null
r=$(now)
end=$(($(date +%s) + $(sc 600) + 60))
until watch_oslog "$r" "[g7-watch] lodged" | grep -q .; do
	[ "$(date +%s)" -ge "$end" ] && abort "the watch placed no request after its reading"
	sleep 2
done

say "The system loses the request and tells the watch nothing"
lost=$(now)
from=$(wc -l < "$RUN/g7.log" | tr -d ' ')   # the sensor log has no dates: count readings after this line
out=$(sim_lose_connect)
echo "$out" | grep -q '"dropped": [1-9]' || abort "nothing to drop: $out"

say "Two sensor readings later the watch has read nothing itself"
end=$(($(date +%s) + $(sc 900) + 120))
until [ "$(tail -n +"$((from + 1))" "$RUN/g7.log" | grep -c 'reading [0-9]*:')" -ge 2 ]; do
	[ "$(date +%s)" -ge "$end" ] && abort "the sensor gave no two readings"
	sleep 3
done
say "sensor gave two readings since the loss"
tsleep 20
expect_none watch "$lost" 'G7 reading' "no watch reading after the lost request"

say "Relaunch the watch app"
sim launch watch
back=$(now)
wait_for watch "$back" 'G7 reading' $(( $(sc 600) + 90 )) >/dev/null

say "Checks"
expect watch "$back" 'G7 reading' "the watch reads again after the relaunch"
verdict
