#!/bin/sh
# Taps in the phone and watch apps, by the labels on screen, through a UI test that attaches to
# the running app (ui/Driver.swift). sim.sh launches the apps; this drives them.
#
#   ui.sh build                      build the two drivers (once)
#   ui.sh start phone|watch          attach a driver to the running app
#   ui.sh ensure phone|watch         the same, unless one is attached and answering
#   ui.sh stop phone|watch
#   ui.sh phone|watch <command>      tap <label> · tap~ <text> · wait <s> <label> · gone <s> <label>
#                                    swipe left|right|up|down · type <text> · crown <turns>
#                                    sys <label> · tree
#
# Exits 1 when a command fails, so a test script can stop there.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
SIM_SOURCED=1 . "$here/sim.sh"
dd=$here/build/ui-dd
q=/tmp/sportmode-ui

build() {
	command -v xcodegen >/dev/null || { echo "needs xcodegen (brew install xcodegen)" >&2; exit 2; }
	(cd "$here/ui" && xcodegen generate --quiet)
	need_sims
	for s in PhoneDriver:$PHONE WatchDriver:$WATCH; do
		xcodebuild build-for-testing -project "$here/ui/SportModeUI.xcodeproj" -scheme "${s%%:*}" \
			-destination "id=${s#*:}" -derivedDataPath "$dd" >"$out/ui-${s%%:*}.log" 2>&1 \
			&& echo "built ${s%%:*}" || { grep " error:" "$out/ui-${s%%:*}.log" | head; exit 1; }
	done
}

start() { # side
	need_sims
	case "$1" in
	phone) dev=$PHONE; id=$PHONE_ID; run=$(ls "$dd"/Build/Products/PhoneDriver_*.xctestrun) ;;
	watch) dev=$WATCH; id=$WATCH_ID; run=$(ls "$dd"/Build/Products/WatchDriver_*.xctestrun) ;;
	*) echo "start phone|watch" >&2; exit 2 ;;
	esac
	stop "$1" 2>/dev/null || true
	mkdir -p "$q"; rm -f "$q/$1".*; echo "$id" >"$q/$1.app"
	# Booted here, not by xcodebuild: xcodebuild shuts down a Simulator it booted when its run
	# ends, and a run ends the drivers with itself.
	xcrun simctl bootstatus "$dev" -b >/dev/null 2>&1 || true
	nohup xcodebuild test-without-building -xctestrun "$run" -destination "id=$dev" \
		>"$out/ui-$1.log" 2>&1 &
	echo $! >"$q/$1.pid"
	i=0; until [ -f "$q/$1.ready" ]; do
		i=$((i + 1)); [ $i -gt 600 ] && { echo "$1 driver did not attach; see $out/ui-$1.log" >&2; exit 1; }
		sleep 0.2
	done
	cut -d' ' -f2- "$q/$1.ready"
}

stop() { # side
	[ -f "$q/$1.pid" ] || return 0
	rm -f "$q/$1.beat"
	printf '%s quit\n' "$(date +%s)$$" >"$q/$1.cmd"
	kill "$(cat "$q/$1.pid")" 2>/dev/null || true
	rm -f "$q/$1.pid"
}

# A driver is alive while its process runs and its heartbeat is fresh.
alive() { # side
	[ -f "$q/$1.pid" ] && kill -0 "$(cat "$q/$1.pid")" 2>/dev/null || return 1
	[ -f "$q/$1.beat" ] && [ $(($(date +%s) - $(stat -f %m "$q/$1.beat"))) -lt 6 ]
}

send() { # side command...
	side=$1; shift
	# A driver ends when a step fails inside XCTest (an element gone mid-tap): attach a new one.
	alive "$side" || {
		[ -f "$q/$side.app" ] || { echo "no $side driver: ui.sh start $side" >&2; return 1; }
		grep -m1 " error: " "$out/ui-$side.log" 2>/dev/null | sed 's/.*error: [^:]*: /last driver ended: /' >&2 || true
		start "$side" >/dev/null
	}
	n=$(date +%s)$$
	printf '%s %s\n' "$n" "$*" >"$q/$side.cmd.tmp" && mv "$q/$side.cmd.tmp" "$q/$side.cmd"
	i=0; until grep -q "^$n " "$q/$side.out" 2>/dev/null; do
		i=$((i + 1)); [ $i -gt 1500 ] && { echo "$side: no answer to $*" >&2; return 1; }
		sleep 0.1
	done
	r=$(cut -d' ' -f2- "$q/$side.out"); echo "$side: $r"
	[ "${r%% *}" = ok ]
}

case "${1:-}" in
build) build ;;
start) start "${2:-}" ;;
ensure) alive "${2:-}" || start "${2:-}" ;;
stop) stop "${2:-}" ;;
phone | watch) s=$1; shift; send "$s" "$@" ;;
*) sed -n 2,12p "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
