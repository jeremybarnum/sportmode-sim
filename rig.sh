# A rig's own sockets, ports and files, sourced after its .sims file by sim.sh, ui.sh and tests/lib.sh.
# Rigs that run at the same time need different slots, set as SLOT=<n> in their .sims-<rig>. Slot 0,
# the default, keeps the paths and ports one rig has always used; slot n uses /tmp/sportmode-<n> and
# ports 8087+10n (the mux), 8088+10n (the G7 simulator) and 8089+10n (the pod simulator).
SLOT=${SLOT:-0}
if [ "$SLOT" = 0 ]; then rig_tmp=/tmp; else rig_tmp=/tmp/sportmode-$SLOT; mkdir -p "$rig_tmp"; fi
APP_SOCK=$rig_tmp/impossible.sock   # the socket the apps' Bluetooth stand-in connects to (the mux)
POD_SOCK=$rig_tmp/impossible-pod.sock
G7_SOCK=$rig_tmp/impossible-g7.sock
MUX_API=:$((8087 + 10 * SLOT))
G7_API=:$((8088 + 10 * SLOT))
POD_API=:$((8089 + 10 * SLOT))
LINK=$rig_tmp/sportmode-sim-link   # SimLink's control file: "down" parts the phone and the watch
export SIMLINK_QUEUE=$rig_tmp/sportmode-sim-queue
export SPORTMODE_UI=$rig_tmp/sportmode-ui   # the tap drivers' commands and answers
