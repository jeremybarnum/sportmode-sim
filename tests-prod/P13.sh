#!/bin/sh
# P13 — The watch's standing copy (the dormant grant an offline start would use) is refreshed when
# the phone's insulin or carbs change: after a bolus and after a carb entry on the phone, the phone
# sends a fresh copy and the watch logs it. The phone sends at most one every 30 s.
TEST=P13
. "$(dirname "$0")/lib.sh"
set -u

say "$TEST — the standing copy follows the phone's insulin and carbs"
reset

say "A 0.5 U bolus on the phone"
b=$(now)
phone_bolus 0.5
wait_for watch "$b" 'dormant grant refreshed' 90
phone_home
sleep 35

say "10 g of carbs on the phone"
c=$(now)
phone_carbs 10
wait_for watch "$c" 'dormant grant refreshed' 90

say "Checks"
expect phone "$b" 'PROGRAM_INSULIN|dose-write\] addPumpEvents' "the bolus was given"
expect_between watch "$b" "$c" 'dormant grant refreshed' "the watch's copy refreshed after the bolus"
expect_within watch "$c" 'dormant grant refreshed' 30 "the watch's copy refreshed within 30 s of the carbs"
expect phone "$c" 'dormant grant refreshed' "the phone sent a fresh copy after the carbs"
verdict
