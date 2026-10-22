#!/bin/sh
# Why a paired phone and watch Simulator stay "(active, disconnected)" on a runner, where on a Mac
# they read "(active, connected)". No apps: a fresh pair, its state over time, CoreSimulator's
# log, the pairing daemons' logs inside each Simulator, and a few things that might connect it.
set -u
say() { printf '\n%s  == %s\n' "$(date +%T)" "$*"; }
rt() { xcrun simctl list runtimes -j | python3 -c "import json,sys; v=[r for r in json.load(sys.stdin)['runtimes'] if r['platform']=='$1' and r.get('isAvailable',True)]; print(v[-1]['identifier'])"; }
dt() { xcrun simctl list runtimes -j | python3 -c "import json,sys; r=[r for r in json.load(sys.stdin)['runtimes'] if r['identifier']=='$1'][0]; t=[t['identifier'] for t in r['supportedDeviceTypes'] if '$2' in t['identifier']]; print(t[0])"; }
pairs() { xcrun simctl list pairs | grep -B2 -A0 "diag" | grep -E "\(active|\(inactive|unavailable" ; xcrun simctl list pairs | grep -A2 "$PAIR" | tr -s ' '; }
CSLOG=$HOME/Library/Logs/CoreSimulator/CoreSimulator.log

say "machine"
sw_vers; sysctl -n machdep.cpu.brand_string hw.ncpu hw.memsize; xcodebuild -version
/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>&1
ifconfig lo0 | head -3
csmark=$(wc -l <"$CSLOG" 2>/dev/null || echo 0)

pr=$(rt iOS); wr=$(rt watchOS)
P=$(xcrun simctl create "diag phone" "$(dt "$pr" iPhone-17-Pro)" "$pr")
W=$(xcrun simctl create "diag watch" "$(dt "$wr" Apple-Watch-Series-11-46mm)" "$wr")
PAIR=$(xcrun simctl pair "$W" "$P")
say "pair $PAIR made (phone $P, watch $W), before boot"; xcrun simctl list pairs | grep -A2 "$PAIR"

say "boot the phone fully, then the watch"
xcrun simctl boot "$P"; xcrun simctl bootstatus "$P" -b >/dev/null
xcrun simctl boot "$W"; xcrun simctl bootstatus "$W" -b >/dev/null
for i in 1 2 3 4 5 6; do echo "$(date +%T) $(xcrun simctl list pairs | grep "$PAIR")"; sleep 20; done

say "pairing services running in each Simulator"
for d in "$P" "$W"; do
	echo "-- $d"; xcrun simctl spawn "$d" launchctl list 2>/dev/null | grep -iE "identityservices|nanoregistry|terminus|companion|bluetooth|pairing|wcd|nanoprefs" | head -20
done

say "listening sockets of the Simulators' host processes"
lsof -nP -iTCP -sTCP:LISTEN 2>/dev/null | grep -iE "Simulator|launchd_sim|identity|terminus|nano" | head -20

say "CoreSimulator.log since the pair was made (pair, gizmo, relay, IDS, error)"
tail -n +"$((csmark + 1))" "$CSLOG" 2>/dev/null | grep -iE "pair|gizmo|relay|ids|companion|error|fail" | cut -c1-260 | head -80

say "inside the phone: pairing and IDS errors (unified log, last 6 min)"
xcrun simctl spawn "$P" log show --last 6m --style compact \
	--predicate 'process IN {"identityservicesd","terminusd","nanoregistryd","companiond","wcd","pairedsyncd"} AND (messageType == error OR messageType == fault OR eventMessage CONTAINS[c] "fail" OR eventMessage CONTAINS[c] "relay" OR eventMessage CONTAINS[c] "connect")' 2>/dev/null | cut -c1-260 | head -60
say "inside the watch: the same"
xcrun simctl spawn "$W" log show --last 6m --style compact \
	--predicate 'process IN {"identityservicesd","terminusd","nanoregistryd","companiond","wcd","pairedsyncd"} AND (messageType == error OR messageType == fault OR eventMessage CONTAINS[c] "fail" OR eventMessage CONTAINS[c] "relay" OR eventMessage CONTAINS[c] "connect")' 2>/dev/null | cut -c1-260 | head -60

say "try: pair_activate"
xcrun simctl pair_activate "$PAIR" 2>&1; sleep 30; xcrun simctl list pairs | grep "$PAIR"

say "try: unpair and pair again with both booted"
xcrun simctl unpair "$PAIR" 2>&1
PAIR=$(xcrun simctl pair "$W" "$P"); echo "new pair $PAIR"
for i in 1 2 3 4; do echo "$(date +%T) $(xcrun simctl list pairs | grep "$PAIR")"; sleep 20; done

say "try: Simulator.app open, both rebooted"
open -a Simulator; sleep 15
xcrun simctl shutdown "$W" "$P"; xcrun simctl boot "$P"; xcrun simctl bootstatus "$P" -b >/dev/null
xcrun simctl boot "$W"; xcrun simctl bootstatus "$W" -b >/dev/null
for i in 1 2 3 4 5 6; do echo "$(date +%T) $(xcrun simctl list pairs | grep "$PAIR")"; sleep 20; done

say "CoreSimulator.log after the tries (pair, gizmo, relay, IDS, error)"
tail -n +"$((csmark + 1))" "$CSLOG" 2>/dev/null | grep -iE "pair|gizmo|relay|ids|companion|error|fail" | cut -c1-260 | tail -60
say "the phone's IDS / terminus lines, last 4 min, any level"
xcrun simctl spawn "$P" log show --last 4m --style compact \
	--predicate 'process IN {"identityservicesd","terminusd","nanoregistryd"}' 2>/dev/null | cut -c1-240 | tail -60
