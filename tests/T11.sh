#!/bin/sh
# T11 — A carb deleted on the watch during a loan. Delete is offered on Loop's own entries, and
# the delete reaches the phone at the hand-back.
TEST=T11
. "$(dirname "$0")/lib.sh"
set -u

say "$TEST — carb deleted on the watch during a loan"
reset

say "Carbs on the phone (13 g); Start on the watch"
phone_carbs 13
sleep 5
start=$(now)
start_loan "$start"

say "On the watch: the carb list, delete the 13 g entry"
watch_page 2
# The row sits below the screen: a swipe up scrolls the page, then the list, to it.
ui watch swipe up
ui watch tap "ACTIVE CARBS"
sleep 2
# The newest row is the last one: scroll until it is on screen (earlier tests can leave more rows).
for i in 1 2 3 4 5; do
	ui watch swipe up
	sleep 1
	watch_labels | grep -q ', 13 g' && break
done
ui watch swipeleft ", 13 g"
d=$(now)
ui watch tap Delete
wait_for watch "$d" 'carb deletion' 30
sleep 1
watch_close_sheets

say "End on the watch"
watch_main
end=$(now)
ui watch tap End
wait_for watch "$end" 'loan closed' 180
wait_for phone "$end" 'carb delete from the watch' 60

say "Checks"
expect watch "$d" 'carb deletion of 13 g recorded' "watch recorded the delete"
expect phone "$end" 'carb delete from the watch applied: 13 g' "the delete reached the phone"
expect_none phone "$end" 'carb delete from the watch failed' "the phone applied it"
verdict
