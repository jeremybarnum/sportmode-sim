#!/bin/sh
# Runs the production line's test scripts on the prod rig: tests-prod/run.sh P1 P4 (no argument: all).
here=$(cd "$(dirname "$0")" && pwd)
RIG=${RIG:-prod} TESTS_DIR=$here exec "$here/../tests/run.sh" "$@"
