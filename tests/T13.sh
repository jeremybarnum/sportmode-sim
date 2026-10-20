#!/bin/sh
# T13 — A Start after an offline start that failed at the takeover. The phone's next grant is
# numbered above the loan the watch started alone, and the watch accepts it.
TEST=T13
. "$(dirname "$0")/lib.sh"
set -u

say "$TEST — Start after a failed offline start"
reset

say "Pod and phone out of reach; offline start; the takeover fails"
sim pod away
sim phone away
start=$(now)
watch_main
ui watch tap "Start Sport Mode"
ui watch wait 20 "Start Anyway"
ui watch tap "Start Anyway"
wait_for watch "$start" 'TAKEOVER FAILED|TAKEOVER ABORTED' 400

say "Pod and phone back; the phone reads the pod"
sim pod back
sim phone back
back=$(now)
wait_reading "$back" 400
sleep 60

say "A normal Start"
"$UI" watch wait 60 "Start Sport Mode" >/dev/null 2>&1 || abort "the watch shows no Start after the failed takeover"
g=$(now)
start_loan "$g"

say "Checks"
expect watch "$start" 'TAKEOVER FAILED|TAKEOVER ABORTED' "the offline takeover failed"
expect phone "$g" 'GRANT — ' "phone granted"
expect watch "$g" 'GRANT received' "watch accepted the grant"
expect_none watch "$g" 'grant REJECTED' "no stale-epoch rejection"
seized=$(lines watch "$start" 'SEIZE confirmed' | sed -n 's/.*epoch [0-9]*→\([0-9]*\).*/\1/p' | tail -1)
granted=$(lines watch "$g" 'GRANT received' | sed -n 's/.*epoch \([0-9]*\),.*/\1/p' | head -1)
if [ -n "$seized" ] && [ -n "$granted" ] && [ "$granted" -gt "$seized" ]; then pass "grant numbered above the offline loan ($granted > $seized)" ""
else fail "grant numbered above the offline loan (granted ${granted:-?}, offline ${seized:-?})" ""; fi
verdict
