#!/bin/sh
# P6 — The watch app relaunched during a loan while the phone's Bluetooth is off (the watch link still
# up). Known edge case, to be fixed in this build: the phone, unable to reach the pod, refuses the
# recovered hand-back; the watch drops to idle and stops resending, and the phone stays loaned. Pass is
# the fixed behaviour: the resends continue until the phone, its Bluetooth back, accepts the offer and
# takes the pod back.
TEST=P6
. "$(dirname "$0")/lib.sh"
set -u

say "$TEST — the watch app relaunched with the phone's Bluetooth off"
reset

say "Start; once active (records streamed), the phone's Bluetooth off; the watch app ends and opens again"
start=$(now)
start_loan "$start"
sleep 30
sim phone radio-off
q=$(now)
sim quit watch
sleep 3
sim launch watch
drivers
say "A minute with the phone unable to reach the pod; then its Bluetooth back"
sleep 60
ui watch tree
grep -q "couldn.t take the pod back yet" /tmp/sportmode-ui/watch.tree && note=yes || note=no
on=$(now)
sim phone radio-on
wait_for phone "$on" 'reclaim VERIFIED' 180

say "Checks"
expect watch "$q" 'alert\] ISSUED .*sessionEnded' "the relaunched watch ended the loan (Sport Mode Ended)"
expect phone "$q" 'offer RX .*released=final' "the recovered offer reached the phone"
expect watch "$q" 'DENIED by phone — .* — drain keeps offering' "the refusal left the watch in its drain, still offering"
expect_between watch "$q" "$on" 'hand-back offer attempt [2-9]|\[timer\] fired handback-resend' "the watch kept resending while the phone could not take the pod"
[ "$note" = yes ] && pass "the watch said the iPhone couldn't take the pod back yet" "" || fail "the watch said the iPhone couldn't take the pod back yet" "not in the watch's element tree"
expect phone "$on" 'reclaim VERIFIED' "the phone took the pod back once its Bluetooth was back"
verdict
