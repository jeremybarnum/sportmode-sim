#!/bin/sh
# P2 — A takeover that cannot reach the pod. The watch's lease runs out (up to 14 reads in 5 minutes),
# it tells the phone the takeover failed, and the phone takes the pod back without a notice.
# Pending decision: a 60 s lease would shorten this.
TEST=P2
. "$(dirname "$0")/lib.sh"
set -u

say "$TEST — a takeover that cannot reach the pod"
reset

say "The pod out of reach; Start on the watch"
sim pod away
start=$(now)
tap_start >/dev/null
wait_for watch "$start" 'takeover ladder start' 60
say "The takeover runs out (up to 6 minutes)"
wait_for watch "$start" 'TAKEOVER FAILED|TAKEOVER ABORTED' 400

say "The pod back in reach; the phone takes it back (no settle on this path: its next read of the pod, up to 11 minutes)"
back=$(now)
sim pod back
i=0
until [ -n "$(pod_lines "$back" 'command;')" ] || [ $i -ge 660 ]; do sleep 10; i=$((i + 10)); done

say "Checks"
expect watch "$start" 'takeover read [0-9]+/14' "the watch kept trying to read the pod"
expect watch "$start" 'TAKEOVER FAILED|TAKEOVER ABORTED' "the takeover failed and was reported"
expect_none watch "$start" 'ACTIVE — epoch' "the loan never started"
expect phone "$start" 'listen END \(watch reported takeover failed' "the phone heard the takeover failed"
l=$(pod_lines "$back" 'command;' | head -1)
if [ -n "$l" ]; then pass "the phone reached the pod again (no other app holds it)" "$(echo "$l" | cut -c1-120)"
else fail "the phone reached the pod again" "no command reached the pod in 11 minutes after it was back"; fi
expect_none phone "$start" 'Watch Loan Not Confirmed|force reclaim' "no notice and no forced take-back"
verdict
