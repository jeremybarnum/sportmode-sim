#!/bin/sh
# Onboards the phone app on fresh Simulators with ui.sh, as README's "Onboard the phone once" does by
# hand: skip setup, Health access, the G7 sensor (code 4321), the Omnipod DASH pod, Closed Loop on.
# For machines that start empty each run (GitHub's macOS runners). The phone app must be running
# (sim.sh launch phone) with the simulators started (sim.sh start -fresh).
#
# Each flow taps the next button it knows until the screen it is after shows, so a screen added or
# skipped by a branch does not stop it. A step that cannot go on prints what is on the screen.
set -u
here=$(cd "$(dirname "$0")/.." && pwd)
UI=$here/ui.sh
SIM=$here/sim.sh
TREE=/tmp/sportmode-ui/phone.tree
out=${ONBOARD_OUT:-$here/build/onboard}
mkdir -p "$out"
n=0

say() { printf '%s  %s\n' "$(date +%T)" "$*"; }

# What the phone shows now: one line per element with a label or identifier, kept as a file per call.
screen() { # name
	n=$((n + 1))
	"$UI" phone tree >/dev/null 2>&1 || { say "(no tree)"; return 0; }
	cp "$TREE" "$out/$(printf %02d $n)-$1.tree"
	grep -E "identifier: '|label: '" "$TREE" | sed -E "s/^ *//; s/, 0x[0-9a-f]+//; s/\{\{[^}]*\}, \{[^}]*\}\}, //" | cut -c1-140 | head -${2:-60}
}

fail() { say "ONBOARDING FAILED: $*"; say "on screen:"; screen fail 120; exit 1; }

shows() { "$UI" phone wait 0 "$1" >/dev/null 2>&1; }
shows_like() { grep -q "label: '[^']*$1" "$TREE" 2>/dev/null || grep -q "identifier: '[^']*$1" "$TREE" 2>/dev/null; }

tap() { # label...: tap the first that is there, in the app or else in a system sheet
	local l
	for l in "$@"; do
		"$UI" phone tap "$l" >/dev/null 2>&1 && { say "tapped $l"; return 0; }
	done
	for l in "$@"; do
		"$UI" phone sys "$l" >/dev/null 2>&1 && { say "tapped $l (system)"; return 0; }
	done
	return 1
}

# System permission alerts (notifications, Bluetooth) answered with Allow, while any come up.
allow_alerts() {
	local i
	for i in 1 2 3; do
		"$UI" phone sys Allow >/dev/null 2>&1 || return 0
		say "allowed a system alert"; sleep 1
	done
}

# Tap the first candidate on screen. A candidate written ~text matches a label containing text.
tap_candidate() { # candidate...
	local c
	"$UI" phone tree >/dev/null 2>&1
	for c in "$@"; do
		case "$c" in
		~*) shows_like "${c#\~}" && "$UI" phone "tap~" "${c#\~}" >/dev/null 2>&1 && { say "tapped ~${c#\~}"; return 0; } ;;
		*) shows "$c" && tap "$c" && return 0 ;;
		esac
	done
	return 1
}

# Tap through a flow until goal shows. Only for a goal that is not on a screen under the flow
# (the element tree lists what a sheet covers).
advance() { # goal seconds candidate...
	local goal=$1 end=$(($(date +%s) + $2))
	shift 2
	while :; do
		case "$goal" in
		~*) "$UI" phone tree >/dev/null 2>&1; shows_like "${goal#\~}" && { say "at $goal"; return 0; } ;;
		*) shows "$goal" && { say "at $goal"; return 0; } ;;
		esac
		[ "$(date +%s)" -ge "$end" ] && fail "did not reach \"$goal\""
		allow_alerts
		tap_candidate "$@" || sleep 2
		sleep 1
	done
}

# Tap through a flow until nothing of it is left to tap: none of the candidates on screen at three
# looks in a row.
drain() { # seconds candidate...
	local end=$(($(date +%s) + $1)) idle=0
	shift
	while [ $idle -lt 3 ]; do
		[ "$(date +%s)" -ge "$end" ] && fail "a flow did not finish (still tapping: $*)"
		allow_alerts
		close_alarms
		if tap_candidate "$@"; then idle=0; sleep 2; else idle=$((idle + 1)); sleep 2; fi
	done
}

# "Turn On Alarms" (a Simulator app cannot have critical alerts) sits where the element tree does not
# reach; it comes with the "Alarms are turned OFF" banner: tap where its Close is, as tests/lib.sh does.
close_alarms() {
	grep -q "Alarms are turned OFF" "$TREE" 2>/dev/null || return 0
	[ -e "$out/alarms-closed" ] && return 0
	touch "$out/alarms-closed"
	"$UI" phone tapxy 127 565 >/dev/null 2>&1 && say "closed Turn On Alarms (by position)"
	sleep 1
	shows BackButton && "$UI" phone tap BackButton >/dev/null 2>&1
	return 0
}

# A switch's own right end, where a tap toggles it (a tap on its label does not).
tap_switch() { # identifier
	local f
	"$UI" phone tree >/dev/null 2>&1
	f=$(grep "identifier: '$1'" "$TREE" | head -1 | grep -oE '\{\{[0-9.-]+, [0-9.-]+\}, \{[0-9.]+, [0-9.]+\}\}' | tr -d '{} ' )
	[ -n "$f" ] || fail "no switch $1"
	set -- $(echo "$f" | tr ',' ' ')
	"$UI" phone tapxy "$(awk -v x="$1" -v w="$3" 'BEGIN { print x + w - 30 }')" "$(awk -v y="$2" -v h="$4" 'BEGIN { print y + h / 2 }')" >/dev/null || fail "could not tap $1"
}

"$UI" ensure phone >/dev/null || fail "no phone driver"

say "Welcome: hold the logo to skip setup"
"$UI" phone wait 90 loopLogo >/dev/null 2>&1 || fail "no Welcome screen"
"$UI" phone press 3 loopLogo >/dev/null || fail "could not hold the logo"
sleep 3
screen after-skip 40

say "Health access and the alarms notice"
drain 180 "Turn On All" "Allow" "Close" "OK" "Not Now"
"$UI" phone wait 30 glucoseHUDView >/dev/null 2>&1 || fail "no status screen after the skip"

say "CGM: Dexcom G7, code 4321"
# The status screen's CGM tile reads "Tap to add" and opens the picker (Settings' row is off screen).
advance pluginPickerItem-G7CGMManager 60 glucoseHUDView
tap pluginPickerItem-G7CGMManager "Dexcom G7 / ONE+" || fail "could not pick Dexcom G7"
advance "Enter Code by Hand" 120 "Pair Sensor" "Sensor Is On, Continue" "Continue" "Allow"
tap "Enter Code by Hand" || fail "no Enter Code by Hand"
sleep 1
"$UI" phone field >/dev/null 2>&1 || true
"$UI" phone type 4321 >/dev/null || fail "could not type the code"
say "typed 4321"
drain 240 "Continue" "Not Now" "Close"

say "Pump: Omnipod DASH, paired, primed, inserted"
advance "~Omnipod" 60 pumpHUDView
"$UI" phone "tap~" Omnipod >/dev/null || fail "could not pick Omnipod"
say "tapped ~Omnipod"
advance "Pair Pod" 180 "Omnipod DASH" "Confirm Pod Type" "~Novolog" "Next" "Continue" "Allow"
advance "Slide to Insert Cannula" 300 "Pair Pod" "~Pair " "Continue" "Allow"
"$UI" phone slide "Slide to Insert Cannula" >/dev/null || fail "could not slide to insert"
say "slid to insert the cannula"
drain 300 "Yes" "Continue" "Finish Setup"

say "Closed Loop on"
"$UI" phone wait 30 settingsViewClosedLoopToggle >/dev/null 2>&1 || tap Settings || fail "no Settings"
"$UI" phone wait 30 settingsViewClosedLoopToggle >/dev/null 2>&1 || fail "no Closed Loop switch in Settings"
tap_switch settingsViewClosedLoopToggle
sleep 2
screen closed-loop 30
tap button_done Done || true
allow_alerts
say "onboarded"
