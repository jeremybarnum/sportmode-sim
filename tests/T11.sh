#!/bin/sh
# T11 — A carb deleted on the watch during a loan. Delete is offered on Loop's own entries, and
# the delete reaches the phone at the hand-back.
TEST=T11
. "$(dirname "$0")/lib.sh"
set -u

say "$TEST — carb deleted on the watch during a loan"
reset

say "Carbs on the phone (11 g); Start on the watch"
phone_carbs 11
sleep 5
start=$(now)
start_loan "$start"

say "On the watch: the carb list, delete the 11 g entry"
watch_page 2
ui watch tap "Active Carbs"
ui watch swipeleft "11 g"
d=$(now)
ui watch tap Delete
wait_for watch "$d" 'carb DELETE' 30
"$UI" watch tap Close >/dev/null 2>&1 || "$UI" watch swipe right >/dev/null 2>&1 || true

say "End on the watch"
watch_main
end=$(now)
ui watch tap End
wait_for watch "$end" 'CLOSED — ' 180
wait_for phone "$end" 'carb DELETE' 60

say "Checks"
expect watch "$d" 'carb DELETE journaled 11 g' "watch recorded the delete"
expect phone "$end" 'carb DELETE from wrist — 11 g' "the delete reached the phone"
expect_none phone "$end" 'carb DELETE MISSED' "the phone applied it"
verdict
