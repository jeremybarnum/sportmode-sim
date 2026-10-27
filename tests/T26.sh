#!/bin/sh
# T26 — the watch with no loan, as the stock watch app: it shows the phone's glucose and insulin on
# board, the phone's carbs in its carb list, a bolus and a preset from the watch go through the phone,
# and with the phone away it shows its own sensor's reading. Checked on the watch's screens, so it runs
# on a build without Sport Mode too (SPORT_MODE=off: no loan to clear first).
TEST=T26
. "$(dirname "$0")/lib.sh"
set -u

say "$TEST — the watch with no loan"
if [ "${SPORT_MODE:-on}" = off ]; then reset_plain; else reset; fi
dismiss_alert
s=$(now)

say "the phone's glucose and insulin on the watch's chart page"
watch_page 2
sleep 2
shown_bg=$(watch_labels | grep -E '^[0-9]{2,3}' | head -1)
sim_bg=$("$SIM" status 2>/dev/null | sed -n '/"latest"/,/}/s/.*"glucose": \([0-9]*\).*/\1/p' | head -1)
iob=$(watch_value "ACTIVE INSULIN")

say "carbs on the phone; the watch's carb list"
# The list's total, before and after: its newest row can be below the visible ones.
open_carb_list() {
	watch_page 2
	# The row is below the chart: scroll to it first.
	ui watch swipe up
	sleep 1
	ui watch "tap~" "ACTIVE CARBS"
	sleep 5
}
open_carb_list
total_before=$(watch_value "TOTAL CARBS")
watch_close_sheets
phone_carbs 12
carbs_listed=no
total_after=
for i in 1 2 3 4 5 6; do
	sleep 10
	open_carb_list
	total_after=$(watch_value "TOTAL CARBS")
	watch_close_sheets
	[ "${total_after%%[!0-9]*}" = "$(( ${total_before%%[!0-9]*} + 12 ))" ] && { carbs_listed=yes; break; }
done

say "a 0.5 U bolus on the watch, which the phone gives"
b=$(now)
watch_bolus_send 0.5
sleep 45
watch_close_sheets
watch_page 2
last_bolus=$(watch_value "LAST BOLUS")

say "Walking started on the watch"
watch_page 1
ui watch tap presets
ui watch wait 10 "Select Preset"
# The second card, Walking: a card is not a labelled control.
ui watch tapxy "104 165"
ui watch wait 10 "Turn Digital Crown to Start"
p=$(now)
ui watch crown 1.5
sleep 15
watch_close_sheets
watch_page 1
ui watch tap presets
sleep 3
preset_active=no; shows watch "Turn Digital Crown to End" && preset_active=yes
e=$(now)
[ "$preset_active" = yes ] && { ui watch crown 1.5; sleep 15; }
preset_after=no; shows watch "Turn Digital Crown to End" && preset_after=yes
watch_close_sheets

say "the phone away, the sensor at 190: the watch's own reading"
sim phone away
sim glucose 190
a=$(now)
watch_page 2
own_bg=
i=0
while [ $i -lt 42 ]; do
	own_bg=$(watch_labels | grep -E '^19[0-9]' | head -1)
	[ -n "$own_bg" ] && break
	sleep 10; i=$((i + 1))
done
sim glucose sine 120 50
sim phone back

say "Checks"
[ -n "$shown_bg" ] && [ -n "$sim_bg" ] && [ "${shown_bg%%[!0-9]*}" -ge $((sim_bg - 30)) ] && [ "${shown_bg%%[!0-9]*}" -le $((sim_bg + 30)) ] \
	&& pass "the watch shows the glucose" "watch $shown_bg, sensor $sim_bg" \
	|| fail "the watch shows the glucose" "watch '${shown_bg:-none}', sensor ${sim_bg:-?}"
[ -n "$iob" ] && [ "$iob" != "-" ] && pass "the watch shows the phone's insulin on board" "$iob" \
	|| fail "the watch shows the phone's insulin on board" "ACTIVE INSULIN '${iob:-none}'"
[ "$carbs_listed" = yes ] && pass "the phone's carbs are in the watch's carb list" "total $total_before → $total_after" \
	|| fail "the phone's carbs are in the watch's carb list" "total $total_before → ${total_after:-none} within a minute"
# The formatter puts a no-break space before the unit.
echo "$last_bolus" | grep -qE '^0[.,]5' && pass "the watch's bolus went through the phone" "LAST BOLUS $last_bolus" \
	|| fail "the watch's bolus went through the phone" "LAST BOLUS '${last_bolus:-none}'"
told=$(oslog "$p" "Set Preset from watch" | head -1)
[ -n "$told" ] && pass "the phone was told of the preset" "$told" || fail "the phone was told of the preset" "no phone line /Set Preset from watch/ since $p"
[ "$preset_active" = yes ] && pass "the watch shows the preset active" "Turn Digital Crown to End" \
	|| fail "the watch shows the preset active" "no active preset on the Presets sheet"
[ "$preset_after" = no ] && pass "ended on the watch, it is gone" "no Turn Digital Crown to End" \
	|| fail "ended on the watch, it is gone" "still shows the active preset"
[ -n "$own_bg" ] && pass "with the phone away the watch shows its own sensor's reading" "$own_bg" \
	|| fail "with the phone away the watch shows its own sensor's reading" "no 19x on the chart page within 7 minutes"
verdict
