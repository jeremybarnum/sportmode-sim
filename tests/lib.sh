# Helpers for the bench test scripts (sourced): steps that say what they do, waits on the apps'
# logs, and checks whose results make the verdict. A test prints its steps, each check with the log
# line that decided it, and PASS or FAIL; it exits 1 on FAIL.

# The harness: this repository, or SPORTMODE_SIM when the tests live in another one.
root=${SPORTMODE_SIM:-$(cd "$(dirname "$0")/.." && pwd)}
SIM=$root/sim.sh
UI=$root/ui.sh
BAND=0.20      # an insulin check's residual counts as clean within ±BAND U
# What differs between lines (another line's lib.sh sets these before sourcing this one): the phone
# cell that opens the take-back sheet, and the watch line that says the pod has a manual bolus.
TAKE_BACK_CELL=${TAKE_BACK_CELL:-Sport Mode}
STATUS_SCREEN=${STATUS_SCREEN:-glucoseHUDView}   # an element only the phone's status screen shows
WATCH_BOLUS=${WATCH_BOLUS:-bolus}                 # the watch control that opens the bolus screen
WATCH_CLOSE=${WATCH_CLOSE:-close-sheet}           # the watch control that closes a sheet
PHONE_BOLUS_FIELD=${PHONE_BOLUS_FIELD-textField_Bolus}   # the phone's bolus amount field; empty: the first text field
PHONE_BOLUS_ACTION=${PHONE_BOLUS_ACTION:-button_bolusAction}   # the phone's deliver button
PHONE_PASSCODE=${PHONE_PASSCODE:-1}                     # a phone bolus asks the Simulator's passcode
PHONE_CARBS_OPEN=${PHONE_CARBS_OPEN:-Add Carbs}             # the phone's carb entry: open, continue, save
PHONE_CARBS_CONTINUE=${PHONE_CARBS_CONTINUE:-button_Continue}
PHONE_CARBS_SAVE=${PHONE_CARBS_SAVE:-button_bolusAction}
BOLUS_ACCEPTED=${BOLUS_ACCEPTED:-MANUAL BOLUS .*ACCEPTED by pod}
T0=$(date +%T) # the test's start: its logs are read from here
failed=0

say() { printf '%s  %s\n' "$(date +%T)" "$*"; }

# A step that cannot be done ends the test, with the apps' last lines since its start (on a machine
# whose logs are not at hand, as a runner's, the job log then says what they were doing).
abort() {
	local side
	say "STOPPED: $*" >&2; failed=1
	for side in phone watch; do
		echo "        last $side lines:" >&2
		"$SIM" since "$side" "$T0" 2>&1 | grep -vE '\[(cgm|glucose|complication)\]' | tail -25 | sed 's/^/          /' >&2
	done
	verdict >&2
}

# ui <side> <command>: a tap or wait in an app; a failure ends the test.
ui() { out=$("$UI" "$@" 2>&1) || abort "$out"; }

sim() { "$SIM" "$@" >/dev/null || abort "sim.sh $*"; }

# An app's log lines since a time (today), matching a regex.
lines() { # side since regex
	"$SIM" since "$1" "$2" "$3" 2>/dev/null
}

# Wait until an app's log has count lines matching regex since a time; prints the last one.
wait_for() { # side since regex seconds [count]
	local _end _n
	_end=$(($(date +%s) + $4))
	while :; do
		_n=$(lines "$1" "$2" "$3" | wc -l | tr -d ' ')
		[ "$_n" -ge "${5:-1}" ] && { lines "$1" "$2" "$3" | tail -1; return 0; }
		[ "$(date +%s)" -ge "$_end" ] && abort "$1 did not log /$3/ within $4 s"
		sleep 2
	done
}

now() { date +%T; }

# The watch app keeps the page it was left on; Sport Mode's controls are on the main page.
WATCH_MAIN_PAGE=${WATCH_MAIN_PAGE:-3}
watch_page() { # n
	local page
	ui watch tree
	page=$(grep -o "page [0-9]* of [0-9]*" /tmp/sportmode-ui/watch.tree | head -1 | cut -d' ' -f2)
	[ -n "$page" ] || return 0
	while [ "$page" -lt "$1" ]; do ui watch swipe left; page=$((page + 1)); done
	while [ "$page" -gt "$1" ]; do ui watch swipe right; page=$((page - 1)); done
}
watch_main() { watch_page "$WATCH_MAIN_PAGE"; }

# Attach the tap drivers (once per run; a no-op when they answer).
drivers() {
	"$UI" ensure phone >/dev/null || abort "no phone driver"
	"$UI" ensure watch >/dev/null || abort "no watch driver"
}

# Checks. Each prints one line: ok or FAIL, what it checks, and the deciding log line.
pass() { printf '  ok    %s\n        %s\n' "$1" "$(echo "$2" | cut -c1-200)"; }
fail() { printf '  FAIL  %s\n        %s\n' "$1" "$(echo "$2" | cut -c1-200)"; failed=1; }

# The app logged a line matching regex since a time.
expect() { # side since regex what
	local l
	# The first line after the time is the one that decides it; a later one may belong to a later part.
	l=$(lines "$1" "$2" "$3" | head -1)
	if [ -n "$l" ]; then pass "$4" "$l"; else fail "$4" "no $1 line /$3/"; fi
}

# The app logged nothing matching regex since a time.
expect_none() { # side since regex what
	local l
	l=$(lines "$1" "$2" "$3" | head -1)
	if [ -z "$l" ]; then pass "$4" "no $1 line /$3/"; else fail "$4" "$l"; fi
}

# Every line matching regex has a residual within the band, and there is at least one.
expect_clean() { # side since regex what
	local all bad
	all=$(lines "$1" "$2" "$3")
	[ -n "$all" ] || { fail "$4" "no $1 line /$3/"; return; }
	bad=$(echo "$all" | awk -v b=$BAND '{ if (match($0, /residual[ =][+-]?[0-9.]+/)) { r = substr($0, RSTART + 9, RLENGTH - 9) + 0; if (r > b || r < -b) print } }')
	if [ -z "$bad" ]; then pass "$4 ($(echo "$all" | wc -l | tr -d ' ') within ±$BAND U)" "$(echo "$all" | tail -1)"
	else fail "$4" "$(echo "$bad" | head -1)"; fi
}

# Seconds from a time (HH:MM:SS[.mmm]) to an app's first line matching regex after it.
seconds_to() { # side since regex
	local l
	l=$(lines "$1" "$2" "$3" | head -1)
	[ -n "$l" ] || return 1
	echo "$2 ${l%% *}" | awk '{ split($1, a, ":"); split($2, b, ":"); printf "%.1f", (b[1]*3600 + b[2]*60 + b[3]) - (a[1]*3600 + a[2]*60 + a[3]) }'
}

# Within a limit: the first line matching regex came at most limit seconds after a time.
# TIME_SLACK=<s> adds that much to every limit, for a slow machine (a GitHub runner).
expect_within() { # side since regex limit what
	local s k=${TIME_SLACK:-0}
	s=$(seconds_to "$1" "$2" "$3") || { fail "$5" "no $1 line /$3/"; return; }
	if awk -v s="$s" -v l="$4" -v k="$k" 'BEGIN { exit !(s <= l + k) }'; then pass "$5 (${s} s)" "$(lines "$1" "$2" "$3" | head -1)"
	else fail "$5 (${s} s, limit $4 s$([ "$k" = 0 ] || echo " + $k s slack"))" "$(lines "$1" "$2" "$3" | head -1)"; fi
}

# An app that crashed during the test fails it: the report and its crashing frame.
CRASH_MARK=$(mktemp -t sportmode-test)
crashes() {
	local f top list
	list=$(mktemp -t sportmode-crashes)
	find "$HOME/Library/Logs/DiagnosticReports" -newer "$CRASH_MARK" \( -name 'Loop-*.ips' -o -name 'WatchApp*.ips' \) >"$list" 2>/dev/null
	while IFS= read -r f; do
		# Only this rig's Simulators: other runs on the Mac leave reports too.
		top=$(python3 - "$f" "$PHONE_SIM_ID" "$WATCH_SIM_ID" <<'PY'
import json, sys
d = json.loads(open(sys.argv[1]).read().split("\n", 1)[1])
if not any(i and i in d.get("procPath", "") for i in sys.argv[2:]):
    sys.exit()
t = [t for t in d["threads"] if t.get("triggered")][0]
f = [x for x in t["frames"] if "assertion" not in x.get("symbol", "") and "precondition" not in x.get("symbol", "")][0]
print(f.get("symbol", "?")[:90], f.get("sourceFile", ""), f.get("sourceLine", ""))
PY
)
		[ -n "$top" ] && fail "no app crash during the test" "$(basename "$f"): $top"
	done <"$list"
	rm -f "$list"
}

verdict() {
	crashes
	if [ "$failed" = 0 ]; then say "$TEST: PASS"; exit 0; else say "$TEST: FAIL"; exit 1; fi
}

# --- Steps shared by the tests ---

RUN=$root/build/run${RIG:+-$RIG}
# The run's time scale (sim.sh start TIME_SCALE=N): a wait the test itself chooses is divided by it.
SCALE=$(cat "$RUN/time-scale" 2>/dev/null || echo 1)
tsleep() { sleep $(awk -v s="$1" -v n="$SCALE" 'BEGIN { v = int(s / n); print (v < 1 ? 1 : v) }'); }
# A duration in seconds divided by the run's time scale, for a test's own timing windows.
sc() { awk -v s="$1" -v n="$SCALE" 'BEGIN { printf "%d", s / n }'; }

# Wait for the sensor simulator's next reading(s) after a time (a reading paces both apps' loops).
wait_reading() { # since seconds [count]
	local _end _n
	_end=$(($(date +%s) + $2))
	while :; do
		_n=$(awk -v t="$1" '$1 > t && /reading [0-9]+:/' "$RUN/g7.log" | wc -l | tr -d ' ')
		[ "$_n" -ge "${3:-1}" ] && { say "sensor reading $(awk -v t="$1" '$1 > t && /reading [0-9]+:/' "$RUN/g7.log" | tail -1 | cut -c1-60)"; return 0; }
		[ "$(date +%s)" -ge "$_end" ] && abort "no sensor reading within $2 s"
		sleep 3
	done
}

# Whether an app is running.
# The app runs with the Bluetooth stand-in injected. An app the system restarted after a crash runs
# without it, with no Bluetooth (OmnipodKit then fakes the pod), and counts as not running.
running() { # phone|watch
	local p
	case "$1" in
	phone) p=$(pgrep -f "$PHONE_SIM_ID.*/Loop.app/Loop" | head -1) ;;
	# The app's own process, or its extension's for a WatchKit app with an extension.
	watch) p=$(pgrep -f "$WATCH_SIM_ID.*/WatchApp.app/(WatchApp|PlugIns/WatchApp Extension)" | head -1) ;;
	esac
	[ -n "$p" ] && ps -wwE -p "$p" -o command= | grep -q DYLD_INSERT_LIBRARIES
}
. "$root/.sims${RIG:+-$RIG}" 2>/dev/null || true
PHONE_SIM_ID=${PHONE_SIM:-${SIMS_PHONE:-}}
WATCH_SIM_ID=${WATCH_SIM:-${SIMS_WATCH:-}}

# Whether a label is on an app's screen now (no waiting).
shows() { "$UI" "$1" wait 0 "$2" >/dev/null 2>&1; }

# The phone takes the pod back from the watch: the status cell, then Reclaim Now.
take_back() {
	local i
	for i in 1 2 3; do
		dismiss_alert
		ui phone "tap~" "$TAKE_BACK_CELL"
		"$UI" phone wait 6 "Reclaim Now" >/dev/null 2>&1 && break
		say "the take-back sheet did not open; tapping the cell again" >&2
	done
	ui phone tap "Reclaim Now"
}

# Like wait_for, but answers instead of ending the test: 0 when the line came, 1 when it did not.
logged_within() { # side since regex seconds
	local _end
	_end=$(($(date +%s) + $4))
	while :; do
		[ -n "$(lines "$1" "$2" "$3")" ] && return 0
		[ "$(date +%s)" -ge "$_end" ] && return 1
		sleep 1
	done
}

# Tap Start on the watch until the watch takes it (a tap right after a page draws or the app wakes
# is often swallowed); prints the time of the tap that registered.
tap_start() {
	local i t
	watch_start_shown
	for i in 1 2 3; do
		t=$(now)
		ui watch tap "Start Sport Mode"
		logged_within watch "$t" 'REQUEST sent' 6 && { echo "$t"; return 0; }
		say "the Start tap was not taken; tapping again" >&2
	done
	abort "the watch did not take the Start tap"
}

# A sheet left open on the watch (a list, the bolus screen) hides the pages.
watch_close_sheets() {
	local i
	for i in 1 2 3; do
		shows watch "$WATCH_CLOSE" || return 0
		"$UI" watch tap "$WATCH_CLOSE" >/dev/null 2>&1 || return 0
		sleep 1
	done
}

# The main page with Start on it; a just-launched app can take a few seconds to show its pages.
watch_start_shown() {
	local i
	for i in 1 2 3 4 5 6; do
		watch_main
		shows watch "Start Sport Mode" && return 0
		sleep 5
	done
	abort "the watch shows no Start"
}

# Start on the watch and wait for the loan.
start_loan() {
	tap_start >/dev/null
	wait_for watch "$1" 'ACTIVE — epoch' 90
}

# An offline start: Start, then Start Anyway when the watch offers it.
offline_start() {
	tap_start >/dev/null
	ui watch wait 20 "Start Anyway"
	ui watch tap "Start Anyway"
	wait_for watch "$1" 'seized loan ACTIVE' 240
}

# The watch's bolus screen: + and − step 0.5 U, so the amount goes to zero and then up in halves;
# Bolus, then the double tap that confirms it in Simulator builds. Waits until the pod has given it.
watch_bolus() { # units (a multiple of 0.5)
	local n t0 shown
	watch_page 1
	ui watch tap "$WATCH_BOLUS"
	ui watch wait 5 "+"
	for n in 1 2 3 4; do "$UI" watch tap "−" >/dev/null 2>&1 || break; done
	n=$(awk -v b="$1" 'BEGIN { printf "%d", b / 0.5 + 0.5 }')
	while [ "$n" -gt 0 ]; do ui watch tap "+"; n=$((n - 1)); done
	ui watch tree
	# The amount is the number just before the "U" beside it.
	shown=$(awk "/label: 'U'\$/ { print prev } { if (match(\$0, /label: '[0-9.]+'/)) prev = substr(\$0, RSTART + 8, RLENGTH - 9) }" /tmp/sportmode-ui/watch.tree | head -1)
	say "watch bolus screen shows ${shown:-?} U"
	t0=$(now)
	ui watch tap Bolus
	ui watch double "Turn Digital"
	wait_for watch "$t0" "$BOLUS_ACCEPTED" 120
	# A pod gives a bolus over time (0.05 U every 2 s): let it finish before the next step.
	sleep $(awk -v b="$1" 'BEGIN { printf "%d", b * 40 + 10 }')
}

# A watch bolus sent, and nothing more: the confirm, without waiting for the pod to accept it.
watch_bolus_send() { # units (a multiple of 0.5)
	local n
	watch_page 1
	ui watch tap "$WATCH_BOLUS"
	ui watch wait 5 "+"
	for n in 1 2 3 4; do "$UI" watch tap "−" >/dev/null 2>&1 || break; done
	n=$(awk -v b="$1" 'BEGIN { printf "%d", b / 0.5 + 0.5 }')
	while [ "$n" -gt 0 ]; do ui watch tap "+"; n=$((n - 1)); done
	ui watch tap Bolus
	ui watch double "Turn Digital"
}

# A watch bolus as fast as the taps go: "+" (default once, 0.5 U each) from whatever the screen
# shows, no zeroing.
watch_bolus_quick() { # [plus taps]
	local n=${1:-1}
	watch_page 1
	ui watch tap "$WATCH_BOLUS"
	while [ "$n" -gt 0 ]; do ui watch tap "+"; n=$((n - 1)); done
	ui watch tap Bolus
	ui watch double "Turn Digital"
}

# A watch bolus started and left running: the same taps, without the wait for delivery.
watch_bolus_start() { # units (a multiple of 0.5)
	local n t0
	watch_page 1
	ui watch tap "$WATCH_BOLUS"
	ui watch wait 5 "+"
	for n in 1 2 3 4; do "$UI" watch tap "−" >/dev/null 2>&1 || break; done
	n=$(awk -v b="$1" 'BEGIN { printf "%d", b / 0.5 + 0.5 }')
	while [ "$n" -gt 0 ]; do ui watch tap "+"; n=$((n - 1)); done
	t0=$(now)
	ui watch tap Bolus
	ui watch double "Turn Digital"
	wait_for watch "$t0" "$BOLUS_ACCEPTED" 120 >/dev/null
	echo "$t0"
}

# The phone's bolus screen: the amount, Deliver, and the Simulator's passcode if it asks for one.
phone_bolus() { # units
	dismiss_alert
	ui phone tap Bolus
	if [ -n "$PHONE_BOLUS_FIELD" ]; then ui phone tap "$PHONE_BOLUS_FIELD"; else ui phone field; fi
	ui phone type "$1"
	ui phone tap Done
	ui phone tap "$PHONE_BOLUS_ACTION"
	sleep 2
	[ "$PHONE_PASSCODE" = 1 ] && { "$UI" phone systype '0000\n' >/dev/null 2>&1 || true; }
	return 0
}

# Back to the starting point every test assumes: everything in range, both apps running, the
# watch idle with Start on screen, the phone holding the pod.
reset() {
	local i t
	say "Reset: everything in range, both apps up, no loan"
	# A stand-in that died (run 25: pod-sim's "Messaging loop is already running", a fatal) fails
	# every test after it: say so, with its last words, and start it again from its saved state.
	if "$SIM" status 2>/dev/null | grep -q ': stopped'; then
		say "stopped: $("$SIM" status 2>/dev/null | grep ': stopped' | cut -d: -f1 | tr '\n' ' ')— starting again; pod's last lines:"
		tail -3 "$RUN/pod.log" 2>/dev/null | cut -c1-160 | sed 's/^/          /'
		"$SIM" start >/dev/null 2>&1 || say "could not start the stand-ins again"
	fi
	"$SIM" phone back >/dev/null 2>&1 || true
	"$SIM" pod back >/dev/null 2>&1 || true
	"$SIM" link up >/dev/null 2>&1 || true
	"$SIM" link normal >/dev/null 2>&1 || true
	"$SIM" link release >/dev/null 2>&1 || true
	"$SIM" link unwedge >/dev/null 2>&1 || true
	[ -e "$RUN/watch-off" ] && "$SIM" watch on >/dev/null 2>&1
	if [ -e "$RUN/watch-rebooted" ]; then
		say "the watch Simulator rebooted since the last reset: the phone app restarts so the watch's queued transfers arrive"
		"$SIM" launch phone >/dev/null; rm -f "$RUN/watch-rebooted"
	fi
	running phone || { say "the phone app is not running with the Bluetooth stand-in: launching it"; "$SIM" launch phone >/dev/null; }
	running watch || { say "the watch app is not running with the Bluetooth stand-in: launching it"; "$SIM" launch watch >/dev/null; }
	drivers
	phone_home
	watch_close_sheets
	watch_main
	for i in 1 2 3; do
		shows watch "Start Sport Mode" && { watch_reads_sensor; return 0; }
		if shows watch "Start Anyway"; then ui watch tap Cancel
		elif shows watch End; then
			say "a loan is running: the phone takes the pod back"
			t=$(now); take_back; wait_for watch "$t" 'CLOSED — ' 120 >/dev/null
		fi
		"$UI" watch wait 60 "Start Sport Mode" >/dev/null 2>&1 && { watch_reads_sensor; return 0; }
		watch_main
	done
	abort "could not get the watch back to Start"
}

# The watch reads the sensor itself during a loan: if it has not in the last 7 minutes, relaunch
# its app and wait for a reading (a restarted simulator can leave the watch's link without a sensor).
watch_reads_sensor() {
	local since
	since=$(date -v-7M +%T)
	[ -n "$(lines watch "$since" 'INGEST src=direct-G7')" ] && return 0
	say "the watch has not read the sensor for 7 minutes: relaunching its app"
	since=$(now)
	"$SIM" launch watch >/dev/null
	"$UI" ensure watch >/dev/null
	wait_for watch "$since" 'INGEST src=direct-G7' 420
}

# The simulated pod's log lines since a time, matching a regex (it stamps whole seconds): what reached
# the pod, whichever app sent it.
pod_lines() { # since regex
	awk -v t="${1%%.*}" 'match($0, /T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]/) { s = substr($0, RSTART + 1, 8); if (s >= t) print s " " $0 }' "$RUN/pod.log" | grep -E "$2"
}

# A line matching regex between two times (one part of a test, before the next part starts).
expect_between() { # side from until regex what
	local l
	l=$(lines "$1" "$2" "$4" | awk -v u="$3" '$1 < u' | tail -1)
	if [ -n "$l" ]; then pass "$5" "$l"; else fail "$5" "no $1 line /$4/ from $2 to $3"; fi
}

# Nothing matching regex between two times (a refusal's window, before the retry).
expect_none_between() { # side from until regex what
	local l
	l=$(lines "$1" "$2" "$4" | awk -v u="$3" '$1 < u' | head -1)
	if [ -z "$l" ]; then pass "$5" "no $1 line /$4/ from $2 to $3"; else fail "$5" "$l"; fi
}

# Exactly n lines matching regex since a time.
expect_count() { # side since regex n what
	local c
	c=$(lines "$1" "$2" "$3" | wc -l | tr -d ' ')
	if [ "$c" = "$4" ]; then pass "$5 ($c)" "$(lines "$1" "$2" "$3" | tail -1)"
	else fail "$5 ($c, expected $4)" "$(lines "$1" "$2" "$3" | tail -1)"; fi
}

# The last line matching regex has a residual between lo and hi.
expect_residual() { # side since regex lo hi what
	local l r
	l=$(lines "$1" "$2" "$3" | tail -1)
	[ -n "$l" ] || { fail "$6" "no $1 line /$3/"; return; }
	r=$(echo "$l" | awk '{ if (match($0, /residual[ =][+-]?[0-9.]+/)) print substr($0, RSTART + 9, RLENGTH - 9) + 0 }')
	if awk -v r="$r" -v lo="$4" -v hi="$5" 'BEGIN { exit !(r != "" && r >= lo && r <= hi) }'; then pass "$6 ($r U)" "$l"
	else fail "$6 (${r:-none} U, expected $4 to $5)" "$l"; fi
}

# After the first line matching from, a line matching until comes with no line matching
# forbidden between them (nothing doses before the stop, say).
expect_between_none() { # side since from until forbidden what
	local all res
	all=$(lines "$1" "$2" '.')
	# The patterns go through the environment: awk -v would strip their backslashes.
	res=$(echo "$all" | A="$3" B="$4" X="$5" awk '
		state == 0 && $0 ~ ENVIRON["A"] { state = 1; next }
		state == 1 && $0 ~ ENVIRON["B"] { state = 2; print "ok " $0; exit }
		state == 1 && $0 ~ ENVIRON["X"] { print "bad " $0; exit }')
	case "$res" in
	ok*) pass "$6" "${res#ok }" ;;
	bad*) fail "$6" "${res#bad }" ;;
	*) fail "$6" "no /$3/ followed by /$4/ in the $1 log" ;;
	esac
}

# Close whatever screen the phone was left on (a carb entry, a bolus, a sheet) until the status
# screen shows: a step that misfired leaves the next test looking at the wrong screen.
phone_home() {
	local i
	for i in 1 2 3 4 5; do
		dismiss_alert
		# The element tree lists the status screen under whatever covers it, so a screen on top
		# must go first: a pushed screen's back button, a sheet's Cancel or Done.
		if shows phone BackButton; then "$UI" phone tap BackButton >/dev/null 2>&1
		elif shows phone Cancel; then "$UI" phone tap Cancel >/dev/null 2>&1
		elif shows phone Done; then "$UI" phone tap Done >/dev/null 2>&1
		else break
		fi
		sleep 1
	done
	"$UI" phone wait 5 "$STATUS_SCREEN" >/dev/null 2>&1 || say "the phone is not on its status screen" >&2
}

# Dismiss the phone's alert, if one is up.
# (The Simulator app cannot have critical alerts, so "Turn On Alarms" comes up now and then.)
dismiss_alert() {
	local b pid
	"$UI" phone tree >/dev/null 2>&1 || return 0
	if grep -q "Alert," /tmp/sportmode-ui/phone.tree; then
		for b in Close OK Dismiss; do shows phone "$b" && { "$UI" phone tap "$b" >/dev/null 2>&1; return 0; }; done
	fi
	# Newer builds put "Turn On Alarms" where the element tree does not reach. It comes up only
	# with the "Alarms are turned OFF" banner, once per launch of the app: tap where its Close is
	# once, and if nothing was there, the tap opened the insulin chart under it: go back.
	grep -q "Alarms are turned OFF" /tmp/sportmode-ui/phone.tree || return 0
	pid=$(grep -o "pid: [0-9]*" /tmp/sportmode-ui/phone.tree | head -1)
	[ "$pid" = "$(cat "$RUN/alarms-closed" 2>/dev/null)" ] && return 0
	echo "$pid" >"$RUN/alarms-closed"
	"$UI" phone tapxy 127 565 >/dev/null 2>&1
	sleep 1
	shows phone BackButton && "$UI" phone tap BackButton >/dev/null 2>&1
	return 0
}

# Make the watch's saved last pod reading look hours old, as if the watch had been off that long
# (the watch must be off: the state file is read at launch). The path is taken while it is on.
watch_state_file() {
	local c
	c=$(xcrun simctl get_app_container "$WATCH_SIM_ID" "$("$SIM" bundle watch)" data) || return 1
	echo "$c/Documents/PodLoanWatchState.plist"
}
age_watch_ledger() { # file hours
	local at
	at=$(date -u -v-"$2"H +%Y-%m-%dT%H:%M:%SZ)
	plutil -replace ledgerLastAt -date "$at" "$1" || abort "could not age the watch's state"
	say "the watch's last pod reading now reads $at"
}

# Carbs entered on the phone, saved without a bolus. The meal screen fills in the recommended
# bolus when there is one ("Save Carbs & Deliver"): clear it, or the save asks for the passcode
# and saves nothing.
phone_carbs() { # grams
	dismiss_alert
	ui phone tap "$PHONE_CARBS_OPEN"
	ui phone type "$1"
	ui phone tap "$PHONE_CARBS_CONTINUE"
	ui phone wait 5 "Meal Bolus"
	ui phone clear
	"$UI" phone tap Done >/dev/null 2>&1 || true
	ui phone tap "$PHONE_CARBS_SAVE"
	# Back on the status screen; the toolbar alone proves nothing, it is on every screen.
	"$UI" phone gone 10 "Meal Bolus" >/dev/null 2>&1 || phone_home
}
