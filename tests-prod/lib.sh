# Helpers for the production line's test scripts (sourced): the bench helpers, on the prod rig, with
# this line's labels and log lines.
export RIG=${RIG:-prod}
TAKE_BACK_CELL=${TAKE_BACK_CELL:-Pump Status}
BOLUS_ACCEPTED=${BOLUS_ACCEPTED:-MANUAL BOLUS delivering}
STATUS_SCREEN=${STATUS_SCREEN:-Pump Status}
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
