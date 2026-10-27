#!/bin/sh
# T25 — a preset on the watch during a loan. While the watch holds the pod, its screens show the
# preset its loop doses with. Jogging is started on the watch with the phone's link cut, so the phone
# is not told; the link comes back and the watch app relaunches, which resumes the loan and fetches the
# phone's settings. The watch still shows Jogging, ends it with the crown, and the phone has both by
# the End.
TEST=T25
. "$(dirname "$0")/lib.sh"
set -u

say "$TEST — a preset on the watch during a loan"
reset
s=$(now)
start_loan "$s"

say "the link to the phone cut; Jogging started on the watch"
sim link down
watch_page 1
ui watch tap presets
ui watch wait 10 "Select Preset"
# The first card, Jogging: a card is not a labelled control.
ui watch tapxy "104 95"
ui watch wait 10 "Turn Digital Crown to Start"
p=$(now)
ui watch crown 1.5
wait_for watch "$p" 'SET-ON-WRIST' 30
sleep 3
watch_close_sheets

say "the link back; the watch app relaunched: the loan resumes and the phone's settings are fetched"
sim link up
r=$(now)
"$SIM" quit watch >/dev/null 2>&1
sleep 2
"$SIM" launch watch >/dev/null || abort "the watch app did not relaunch"
wait_for watch "$r" 'RESUMED — epoch' 120
drivers
sleep 10
watch_close_sheets
watch_page 1
ui watch tap presets
sleep 3
active_shown=no; shows watch "Turn Digital Crown to End" && active_shown=yes
list_shown=no; shows watch "Select Preset" && list_shown=yes

say "Jogging ended on the watch"
e=$(now)
ui watch crown 1.5
wait_for watch "$e" 'SET-ON-WRIST · CLEARED' 30
sleep 3
active_after=no; shows watch "Turn Digital Crown to End" && active_after=yes
watch_close_sheets

say "End on the watch"
watch_main
end=$(now)
ui watch tap End
wait_for watch "$end" 'CLOSED — ' 180
wait_for phone "$end" 'reconcile\[AUTHORITATIVE\]' 120

say "Checks"
expect watch "$p" 'phone not told' "the phone was not told of the preset (link cut)"
expect watch "$p" 'APPLIED .*Jogging' "the loop doses with the preset"
expect watch "$r" 'RESUMED — epoch' "the loan resumed after the relaunch"
[ "$active_shown" = yes ] && [ "$list_shown" = no ] \
	&& pass "after the relaunch the watch shows Jogging active" "Turn Digital Crown to End" \
	|| fail "after the relaunch the watch shows Jogging active" "active screen: $active_shown, preset list: $list_shown"
expect watch "$e" 'CLEARED — schedules resolve unscaled' "the loop doses without it once ended"
[ "$active_after" = no ] && pass "the watch stops showing it" "no Turn Digital Crown to End" \
	|| fail "the watch stops showing it" "still shows the active preset"
applied=$(oslog "$p" "from watch: APPLIED" | head -1)
[ -n "$applied" ] && pass "the phone has the preset" "$applied" || fail "the phone has the preset" "no phone line /from watch: APPLIED/ since $p"
cleared=$(oslog "$e" "from watch: CLEARED" | head -1)
[ -n "$cleared" ] && pass "the phone has its end" "$cleared" || fail "the phone has its end" "no phone line /from watch: CLEARED/ since $e"
expect_clean phone "$end" 'reconcile\[AUTHORITATIVE\]' "hand-back's check"
verdict
