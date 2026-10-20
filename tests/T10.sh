#!/bin/sh
# T10 — When the offline start is offered. The Start's request is the question; when the phone
# does not answer within 10 s, a watch holding the phone's standing copy offers to start without
# it: (a) with the phone out of reach, (c) with the phone in reach but its app not running.
TEST=T10
. "$(dirname "$0")/lib.sh"
set -u

say "$TEST — when the offline start is offered"
reset

say "(a) Phone out of reach; Start on the watch"
sim phone away
watch_main
a=$(now)
ui watch tap "Start Sport Mode"
ui watch wait 20 "Start Anyway"
ui watch tap Cancel
sim phone back
sleep 15

say "(c) Phone app not running; Start on the watch"
sim quit phone
sleep 3
watch_main
c=$(now)
ui watch tap "Start Sport Mode"
"$UI" watch wait 20 "Start Anyway" >/dev/null 2>&1 && ui watch tap Cancel
sim launch phone
sleep 10

say "Checks"
expect_within watch "$a" 'offering offline start' 12 "(a) offered after the 10 s wait, phone out of reach"
expect_within watch "$c" 'offering offline start' 12 "(c) offered after the 10 s wait, phone app not running"
expect_none watch "$a" 'SEIZE confirmed' "no loan started without the confirm"
verdict
