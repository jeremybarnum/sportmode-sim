# Helpers for the bench test scripts (sourced): steps that say what they do, waits on the apps'
# logs, and checks whose results make the verdict. A test prints its steps, each check with the log
# line that decided it, and PASS or FAIL; it exits 1 on FAIL.

root=$(cd "$(dirname "$0")/.." && pwd)
SIM=$root/sim.sh
UI=$root/ui.sh
BAND=0.20      # an insulin check's residual counts as clean within ±BAND U
T0=$(date +%T) # the test's start: its logs are read from here
failed=0

say() { printf '%s  %s\n' "$(date +%T)" "$*"; }

# A step that cannot be done ends the test.
abort() { say "STOPPED: $*"; failed=1; verdict; }

# ui <side> <command>: a tap or wait in an app; a failure ends the test.
ui() { out=$("$UI" "$@" 2>&1) || abort "$out"; }

sim() { "$SIM" "$@" >/dev/null || abort "sim.sh $*"; }

# An app's log lines since a time (today), matching a regex.
lines() { # side since regex
	"$SIM" since "$1" "$2" "$3" 2>/dev/null
}

# Wait until an app's log has count lines matching regex since a time; prints the last one.
wait_for() { # side since regex seconds [count]
	end=$(($(date +%s) + $4))
	while :; do
		n=$(lines "$1" "$2" "$3" | wc -l | tr -d ' ')
		[ "$n" -ge "${5:-1}" ] && { lines "$1" "$2" "$3" | tail -1; return 0; }
		[ "$(date +%s)" -ge "$end" ] && abort "$1 did not log /$3/ within $4 s"
		sleep 2
	done
}

now() { date +%T; }

# The watch app keeps the page it was left on; Sport Mode's controls are on the main page.
WATCH_MAIN_PAGE=${WATCH_MAIN_PAGE:-3}
watch_main() {
	ui watch tree
	page=$(grep -o "page [0-9]* of [0-9]*" /tmp/sportmode-ui/watch.tree | head -1 | cut -d' ' -f2)
	[ -n "$page" ] || return 0
	while [ "$page" -lt "$WATCH_MAIN_PAGE" ]; do ui watch swipe left; page=$((page + 1)); done
	while [ "$page" -gt "$WATCH_MAIN_PAGE" ]; do ui watch swipe right; page=$((page - 1)); done
}

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
	l=$(lines "$1" "$2" "$3" | tail -1)
	if [ -n "$l" ]; then pass "$4" "$l"; else fail "$4" "no $1 line /$3/"; fi
}

# The app logged nothing matching regex since a time.
expect_none() { # side since regex what
	l=$(lines "$1" "$2" "$3" | head -1)
	if [ -z "$l" ]; then pass "$4" "no $1 line /$3/"; else fail "$4" "$l"; fi
}

# Every line matching regex has a residual within the band, and there is at least one.
expect_clean() { # side since regex what
	all=$(lines "$1" "$2" "$3")
	[ -n "$all" ] || { fail "$4" "no $1 line /$3/"; return; }
	bad=$(echo "$all" | awk -v b=$BAND '{ if (match($0, /residual[ =][+-]?[0-9.]+/)) { r = substr($0, RSTART + 9, RLENGTH - 9) + 0; if (r > b || r < -b) print } }')
	if [ -z "$bad" ]; then pass "$4 ($(echo "$all" | wc -l | tr -d ' ') within ±$BAND U)" "$(echo "$all" | tail -1)"
	else fail "$4" "$(echo "$bad" | head -1)"; fi
}

# Seconds from a time (HH:MM:SS[.mmm]) to an app's first line matching regex after it.
seconds_to() { # side since regex
	l=$(lines "$1" "$2" "$3" | head -1)
	[ -n "$l" ] || return 1
	echo "$2 ${l%% *}" | awk '{ split($1, a, ":"); split($2, b, ":"); printf "%.1f", (b[1]*3600 + b[2]*60 + b[3]) - (a[1]*3600 + a[2]*60 + a[3]) }'
}

# Within a limit: the first line matching regex came at most limit seconds after a time.
expect_within() { # side since regex limit what
	s=$(seconds_to "$1" "$2" "$3") || { fail "$5" "no $1 line /$3/"; return; }
	if awk -v s="$s" -v l="$4" 'BEGIN { exit !(s <= l) }'; then pass "$5 (${s} s)" "$(lines "$1" "$2" "$3" | head -1)"
	else fail "$5 (${s} s, limit $4 s)" "$(lines "$1" "$2" "$3" | head -1)"; fi
}

verdict() {
	if [ "$failed" = 0 ]; then say "$TEST: PASS"; exit 0; else say "$TEST: FAIL"; exit 1; fi
}
