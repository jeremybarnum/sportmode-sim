# Helpers for the production line's test scripts (sourced): the bench helpers, on the prod rig, with
# this line's labels and log lines.
export RIG=${RIG:-prod}
TAKE_BACK_CELL=${TAKE_BACK_CELL:-Pump Status}
BOLUS_ACCEPTED=${BOLUS_ACCEPTED:-MANUAL BOLUS delivering}
STATUS_SCREEN=${STATUS_SCREEN:-Pump Status}
WATCH_BOLUS=${WATCH_BOLUS:-Bolus}
WATCH_CLOSE=${WATCH_CLOSE:-Close}
PHONE_BOLUS_FIELD=${PHONE_BOLUS_FIELD-}
PHONE_BOLUS_ACTION=${PHONE_BOLUS_ACTION:-Deliver}
PHONE_PASSCODE=${PHONE_PASSCODE:-0}
PHONE_CARBS_OPEN=${PHONE_CARBS_OPEN:-Add Meal}
PHONE_CARBS_CONTINUE=${PHONE_CARBS_CONTINUE:-Continue}
PHONE_CARBS_SAVE=${PHONE_CARBS_SAVE:-Save without Bolusing}
. "$(dirname "$0")/../tests/lib.sh"

# The workout keepalive starts with the loan, once the watch has Health permission to write
# workouts; without it the check is reported as not made, since only a person can grant it.
check_keepalive() { # since
	if [ -n "$(lines watch "$1" 'workout share auth NOT granted')" ]; then
		printf '  --    %s\n        %s\n' "workout keepalive started: NOT CHECKED, no Health permission on this watch" \
			"$(lines watch "$1" 'workout share auth NOT granted' | tail -1 | cut -c1-160)"
	else
		expect watch "$1" 'HKWorkoutSession\(\.other\) started' "workout keepalive started"
	fi
}

# Closed loop on, on the phone: a test that ends in an open loop (an unverified or unexplained
# take-back) leaves it off, and the next test's watch would inherit an open loop.
closed_loop_on() {
	ui phone tap Settings
	ui phone wait 5 "Closed Loop"
	ui phone tree
	if grep -q "label: 'Closed Loop', value: 0" /tmp/sportmode-ui/phone.tree; then
		ui phone tap "Closed Loop"
		say "closed loop switched back on"
	fi
	ui phone tap Done
}

# The texts of a Simulator's pending and delivered notifications.
notifications() { # phone|watch [pending|delivered]
	case "$1" in
	phone) python3 "$root/tests/notifications.py" "$PHONE_SIM_ID" ${2:-} ;;
	watch) python3 "$root/tests/notifications.py" "$WATCH_SIM_ID" ${2:-} ;;
	esac
}

# The watch's glance shows text matching a regex within some seconds (an alert on top is closed
# first, and the glance brought to the front).
watch_shows_text() { # regex [seconds]
	local end
	end=$(($(date +%s) + ${2:-20}))
	shows watch OK && "$UI" watch tap OK >/dev/null 2>&1
	watch_close_sheets
	watch_main
	while :; do
		"$UI" watch tree >/dev/null 2>&1
		grep -Eq "$1" /tmp/sportmode-ui/watch.tree && return 0
		[ "$(date +%s)" -ge "$end" ] && return 1
		sleep 2
	done
}
