#!/bin/sh
# Which way of installing makes the phone app see the watch app (WCSession isWatchAppInstalled,
# logged by the phone as "appInstalled=true") on a runner's paired Simulators. Each strategy gets a
# fresh pair; the apps are launched plainly (no Bluetooth stand-in, nothing onboarded), since the
# phone logs its link line from launch. Prints one verdict line per strategy.
set -u
here=$(cd "$(dirname "$0")/.." && pwd)
APPS=$here/build/dd/Build/Products
PHONE_APP=$APPS/Debug-iphonesimulator/Loop.app
WATCH_APP=$APPS/Debug-watchsimulator/WatchApp.app
PID=$(defaults read "$PHONE_APP/Info.plist" CFBundleIdentifier)
WID=$(defaults read "$WATCH_APP/Info.plist" CFBundleIdentifier)
say() { printf '%s  %s\n' "$(date +%T)" "$*"; }

# PROBE_VERSIONS: the runtime versions to try ("26.4 26.2"); strategy A on each.
rt() { xcrun simctl list runtimes -j | python3 -c "import json,sys; v=[r for r in json.load(sys.stdin)['runtimes'] if r['platform']=='$1' and r['version'].startswith('$2')]; print(v[-1]['identifier'] if v else '')"; }
dt() { xcrun simctl list runtimes -j | python3 -c "import json,sys; r=[r for r in json.load(sys.stdin)['runtimes'] if r['identifier']=='$1'][0]; print([t['identifier'] for t in r['supportedDeviceTypes'] if '$2' in t['identifier']][0])"; }
say "phone app $PID, watch app $WID"
say "phone app embeds: $(ls "$PHONE_APP/Watch" 2>/dev/null | tr '\n' ' ')"
plutil -p "$WATCH_APP/Info.plist" | grep -E "WKCompanion|WKApplication|WKWatchOnly|CFBundleIdentifier"

new_pair() { # name -> sets P W PAIR
	P=$(xcrun simctl create "probe phone $1" "$pt" "$pr")
	W=$(xcrun simctl create "probe watch $1" "$wt" "$wr")
	PAIR=$(xcrun simctl pair "$W" "$P")
	xcrun simctl boot "$P"; xcrun simctl boot "$W"
	xcrun simctl bootstatus "$P" -b >/dev/null; xcrun simctl bootstatus "$W" -b >/dev/null
}

# The phone's link lines since a time, from its own log in Documents.
phone_link() { # since
	c=$(xcrun simctl get_app_container "$P" "$PID" data 2>/dev/null) || return 0
	awk -v t="$(date +%F) $1" '($1 " " $2) >= t' "$c/Documents/g7phone-latest.log" 2>/dev/null | grep "\[link\]" | cut -c12-160
}

# Launch the phone app and wait up to 90 s for a link line; say whether it saw the watch app.
check() { # strategy
	local t i l
	t=$(date +%T)
	xcrun simctl terminate "$P" "$PID" 2>/dev/null; xcrun simctl launch "$P" "$PID" >/dev/null
	for i in $(seq 1 18); do
		l=$(phone_link "$t" | tail -1)
		[ -n "$l" ] && break
		sleep 5
	done
	say "watch apps: $(xcrun simctl listapps "$W" 2>/dev/null | grep -c "$WID") match(es) for $WID"
	case "$l" in
	*appInstalled=true*) say "VERDICT $1: SEES the watch app — $l" ;;
	"") say "VERDICT $1: no link line in 90 s" ;;
	*) say "VERDICT $1: does not see it — $l" ;;
	esac
}

done_pair() { xcrun simctl shutdown "$P" "$W" 2>/dev/null; xcrun simctl delete "$P" "$W" 2>/dev/null; }

# The Mac where the phone does see the watch app runs Simulator.app the whole time, and uses
# an iPhone 17 Pro and an Apple Watch Series 11 (46mm) on 26.5.
pick() { # runtime pattern fallback
	xcrun simctl list runtimes -j | python3 -c "import json,sys; r=[r for r in json.load(sys.stdin)['runtimes'] if r['identifier']=='$1'][0]; t=[t['identifier'] for t in r['supportedDeviceTypes'] if '$2' in t['identifier']]; print(t[0] if t else '$3')"
}
pairs() { xcrun simctl list pairs | grep -A3 "probe" | tr -s ' ' | head -8; }
open -a Simulator; sleep 15
say "Simulator.app: $(pgrep -x Simulator >/dev/null && echo running || echo not running)"
for v in ${PROBE_VERSIONS:-26.5}; do
	pr=$(rt iOS "$v"); wr=$(rt watchOS "$v")
	[ -n "$pr" ] && [ -n "$wr" ] || { say "no $v runtimes"; continue; }
	pt=$(pick "$pr" iPhone-17-Pro "$(dt "$pr" iPhone)"); wt=$(pick "$wr" Apple-Watch-Series-11-46mm "$(dt "$wr" Apple-Watch)")
	say "$v with Simulator.app: $pt, $wt"
	new_pair "$v"
	say "pair after boot:"; pairs
	xcrun simctl install "$P" "$PHONE_APP"; xcrun simctl install "$W" "$WATCH_APP"
	xcrun simctl launch "$W" "$WID" >/dev/null; sleep 20
	check "$v-1"; say "pair:"; pairs
	sleep 20; check "$v-2"
	done_pair
done
