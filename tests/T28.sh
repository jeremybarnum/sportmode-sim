#!/bin/sh
# T28 — A Start the watch never confirms, with no countdown on the phone. The pod is out of the
# watch's reach, so its takeover stalls; once it has the grant, the link to the phone is cut, so
# neither a confirmation nor a failure can reach the phone. The phone asks nothing and takes the pod
# back at its first cycle after the grant's 60 s lease, with its notice; the watch, past the lease,
# never takes the pod.
TEST=T28
. "$(dirname "$0")/lib.sh"
set -u

say "$TEST — an unconfirmed Start is taken back at the phone's next cycle"
reset

say "Pod and sensor out of the watch's reach; Start"
sim watch away
s=$(now)
tap_start >/dev/null
wait_for watch "$s" 'grant received for loan' 60
g=$(now)

say "The link cut once the watch has the grant"
sim link down
wait_for phone "$s" 'the takeover lease ended unconfirmed' 300
back=$(now)

say "Link and reach restored"
sim link up
sim watch back
wait_for watch "$g" 'takeover failed|grant expired|loan closed|no loan is live' 240

say "Checks"
expect phone "$s" 'lending the pod to the watch' "the phone lent the pod"
expect_none phone "$s" 'takeover not confirmed after|whether the grant arrived' "no countdown, no question"
expect phone "$s" 'loan abandoned, this phone keeps the pod: the takeover lease ended unconfirmed' "taken back past the lease"
l1=$(lines phone "$s" 'lending the pod to the watch' | head -1 | cut -c1-8)
l2=$(lines phone "$s" 'the takeover lease ended unconfirmed' | head -1 | cut -c1-8)
gap=$(( $(date -j -f %T "$l2" +%s) - $(date -j -f %T "$l1" +%s) ))
[ "$gap" -ge 60 ] && pass "not before the lease ended" "$gap s after lending" || fail "not before the lease ended" "$gap s after lending"
expect_none watch "$s" 'loan [0-9]+ active' "the watch never took the pod"
verdict
