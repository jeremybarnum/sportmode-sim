#!/bin/sh
# Loop's Sport Mode in the Simulators, with no devices: the phone app and the watch app in a paired
# pair of Simulators, a simulated pod and a simulated sensor on the Mac, joined by ImpossiBLE. See
# README.md for setup and how the bench tests map to these commands.
#
#   sim.sh build            clone and build the simulators and libraries into build/ (idempotent)
#   sim.sh sims             create and pair a phone and a watch Simulator for the run (once)
#   sim.sh apps             build Loop's phone and watch apps for the Simulators (WORKSPACE=...)
#   sim.sh install          install the built apps on the Simulators
#   sim.sh start [-fresh|-fresh-pod]  start the pod and sensor simulators and the mux
#                           (-fresh: a new pod and sensor; -fresh-pod: a new pod only)
#   sim.sh stop             stop them
#   sim.sh status           what is running, and the pod's and sensor's state
#   sim.sh launch phone|watch   launch an app with the libraries injected
#   sim.sh log phone|watch|pod|g7|mux [lines]          tail that log
#   sim.sh since phone|watch HH:MM:SS [regex]          an app's log lines from that time (today)
#
# The physical situations of the bench tests:
#   sim.sh phone away|back  the phone's radios off and on: no watch, no pod, no sensor
#   sim.sh pod away|back    the pod out of reach of both, and back
#   sim.sh watch off|on     shut the watch Simulator down; boot it and launch the watch app
#   sim.sh quit phone|watch end the app (a force quit)
#   sim.sh range            what is out of range now
#
# Environment: PHONE_SIM, WATCH_SIM (Simulator UDIDs; default: the pair `sims` made; zsh keeps
# WATCH for itself), WORKSPACE (a
# LoopWorkspace checkout, for `apps`), APPS (a Build/Products directory, default build/dd's),
# MUX_TRACE=1 (the mux logs every request and event for a peripheral).
set -eu

here=$(cd "$(dirname "$0")" && pwd)
out=$here/build
run=$out/run

# The simulators, at the commits this harness was tested with (LoopKit/g7sim and LoopKit/pod with
# the changes proposed upstream; g7sim builds ImpossiBLE with its own patches).
G7SIM=https://github.com/jeremybarnum/g7sim; G7SIM_COMMIT=82add04
POD=https://github.com/jeremybarnum/pod;     POD_COMMIT=ab76d1a

[ -f "$here/.sims" ] && . "$here/.sims"
PHONE=${PHONE_SIM:-${SIMS_PHONE:-}}
WATCH=${WATCH_SIM:-${SIMS_WATCH:-}}
APPS=${APPS:-$out/dd/Build/Products}
PHONE_APP=$APPS/Debug-iphonesimulator/Loop.app
WATCH_APP=$APPS/Debug-watchsimulator/WatchApp.app
POD_SOCK=/tmp/impossible-pod.sock
G7_SOCK=/tmp/impossible-g7.sock
POD_API=:8089
G7_API=:8088
MUX_API=:8087
LINK=/tmp/sportmode-sim-link   # SimLink's control file: "down" parts the phone and the watch
export SIMLINK_QUEUE=/tmp/sportmode-sim-queue

need_sims() {
	[ -n "$PHONE" ] && [ -n "$WATCH" ] || { echo "no Simulators: run 'sim.sh sims', or set PHONE_SIM and WATCH_SIM" >&2; exit 2; }
}

# Bundle ids from the built apps: they follow the workspace's own configuration.
bundle_id() { defaults read "$1/Info.plist" CFBundleIdentifier 2>/dev/null; }
PHONE_ID=${PHONE_ID:-$(bundle_id "$PHONE_APP" || true)}
WATCH_ID=${WATCH_ID:-$(bundle_id "$WATCH_APP" || true)}

clone() { # url commit dir
	if [ ! -d "$3/.git" ]; then git clone --quiet "$1" "$3"; fi
	git -C "$3" fetch --quiet origin
	git -C "$3" checkout --quiet --force "$2"
}

build_link() { # sdk target out
	xcrun -sdk "$1" clang -dynamiclib -fobjc-arc -fmodules -target "$2" \
		-framework Foundation -framework WatchConnectivity -install_name @rpath/libSimLink.dylib \
		"$here/SimLink.m" -o "$out/$3"
	echo "built $3"
}

build() {
	mkdir -p "$out" "$run"
	clone $G7SIM $G7SIM_COMMIT "$out/g7sim"
	clone $POD $POD_COMMIT "$out/pod"
	# ImpossiBLE for the iOS and watchOS Simulators, with g7sim's fixes.
	"$out/g7sim/simulator/build-impossible.sh" "$out/impossible" >/dev/null && echo "built ImpossiBLE (iOS, watchOS)"
	build_link iphonesimulator arm64-apple-ios15.0-simulator libSimLink-ios.dylib
	build_link watchsimulator arm64-apple-watchos10.0-simulator libSimLink-watch.dylib
	go -C "$out/pod" build -o "$out/pod-sim" . && echo "built pod-sim"
	go -C "$out/g7sim" build -o "$out/g7-sim" . && echo "built g7-sim"
	go -C "$out/g7sim" build -o "$out/impossible-mux" ./cmd/impossible-mux && echo "built impossible-mux"
}

# A pair of its own, so nothing else erases the onboarding. The newest iPhone and Apple Watch
# device types and runtimes installed, unless PHONE_TYPE, WATCH_TYPE, PHONE_RUNTIME, WATCH_RUNTIME say.
sims() {
	if [ -n "${SIMS_PHONE:-}" ]; then echo "already made: phone $SIMS_PHONE, watch $SIMS_WATCH (.sims)"; return; fi
	# The newest runtime of a platform, and the newest model of a family it supports (both lists
	# run newest-first).
	runtime() { xcrun simctl list runtimes -j | python3 -c "import json,sys; v=[r for r in json.load(sys.stdin)['runtimes'] if r['platform']=='$1' and r.get('isAvailable',True)]; print(v[-1]['identifier'])"; }
	model() { xcrun simctl list runtimes -j | python3 -c "import json,sys; r=[r for r in json.load(sys.stdin)['runtimes'] if r['identifier']=='$1'][0]; print([t['identifier'] for t in r['supportedDeviceTypes'] if '$2' in t['identifier']][0])"; }
	pr=${PHONE_RUNTIME:-$(runtime iOS)}; wr=${WATCH_RUNTIME:-$(runtime watchOS)}
	pt=${PHONE_TYPE:-$(model "$pr" iPhone)}; wt=${WATCH_TYPE:-$(model "$wr" Apple-Watch)}
	p=$(xcrun simctl create "Sport Mode Phone" "$pt" "$pr")
	w=$(xcrun simctl create "Sport Mode Watch" "$wt" "$wr")
	xcrun simctl pair "$w" "$p" >/dev/null
	printf 'SIMS_PHONE=%s\nSIMS_WATCH=%s\n' "$p" "$w" >"$here/.sims"
	xcrun simctl boot "$p"; xcrun simctl boot "$w"
	echo "phone $p, watch $w (saved in .sims)"
}

started() { pgrep -f "$out/$1 " >/dev/null 2>&1; }

start() {
	fresh=${1:-}
	podfresh=$fresh; [ "$fresh" = -fresh-pod ] && { fresh=; podfresh=-fresh; }
	mkdir -p "$run"
	started pod-sim || { nohup "$out/pod-sim" -transport impossible -socket $POD_SOCK -api $POD_API \
		-state "$run/pod-state.toml" ${podfresh:+-fresh} >"$run/pod.log" 2>&1 & }
	# The stand-in sensor G7SensorKit offers in the Simulator, so "scan" and manual entry both find it.
	# In a subshell for its working directory, which exec hands to the simulator, so nothing is left
	# holding the terminal.
	started g7-sim || { (cd "$run" && exec nohup "$out/g7-sim" -transport impossible -socket $G7_SOCK -api $G7_API \
		${fresh:+-fresh -code 4321 -serial 7810293746}) >"$run/g7.log" 2>&1 </dev/null & }
	sleep 1
	# The mux refuses the socket if another provider (ImpossiBLE's menu bar app?) holds it; its log says.
	started impossible-mux || { nohup "$out/impossible-mux" -api $MUX_API $G7_SOCK $POD_SOCK >"$run/mux.log" 2>&1 & }
	sleep 1
	status
	started impossible-mux || { tail -2 "$run/mux.log"; exit 1; }
}

stop() {
	for p in impossible-mux pod-sim g7-sim; do pkill -f "$out/$p " 2>/dev/null && echo "stopped $p" || true; done
	rm -f /tmp/impossible.sock $POD_SOCK $G7_SOCK
}

status() {
	for p in pod-sim g7-sim impossible-mux; do started $p && echo "$p: running" || echo "$p: stopped"; done
	curl -s -m 3 "localhost${POD_API}/status" | head -c 300; echo
	curl -s -m 3 "localhost${G7_API}/status" | head -c 300; echo
}

apps() {
	need_sims
	[ -n "${WORKSPACE:-}" ] && [ -d "$WORKSPACE/LoopWorkspace.xcworkspace" ] || { echo "set WORKSPACE to a LoopWorkspace checkout" >&2; exit 2; }
	mkdir -p "$run"
	xcodebuild -workspace "$WORKSPACE/LoopWorkspace.xcworkspace" -scheme LoopWorkspace -configuration Debug \
		-destination "platform=iOS Simulator,id=$PHONE" -derivedDataPath "$(dirname "$(dirname "$APPS")")" \
		ONLY_ACTIVE_ARCH=YES build >"$run/apps-build.log" 2>&1 || { grep " error:" "$run/apps-build.log" | head; exit 1; }
	# An incremental build can leave a rebuilt framework unsigned in the app, and the app then
	# cannot load that plugin: sign what is unsigned, ad hoc, as the build signs the rest.
	for f in "$PHONE_APP"/Frameworks/* "$PHONE_APP"/PlugIns/* "$WATCH_APP"/Frameworks/* "$WATCH_APP"/PlugIns/*; do
		[ -e "$f" ] || continue
		codesign -dv "$f" 2>&1 | grep -q "not signed" && codesign --force --sign - "$f" >/dev/null 2>&1 && echo "signed $(basename "$f")"
	done
	echo "built $(defaults read "$PHONE_APP/Info.plist" CFBundleVersion)"
}

install() {
	need_sims
	xcrun simctl install "$PHONE" "$PHONE_APP" && echo "phone: installed $(defaults read "$PHONE_APP/Info.plist" CFBundleVersion)"
	xcrun simctl install "$WATCH" "$WATCH_APP" && echo "watch: installed $(defaults read "$WATCH_APP/Info.plist" CFBundleVersion)"
}

launch() {
	need_sims
	case "$1" in
	phone) dev=$PHONE; id=$PHONE_ID; lib=$out/impossible/libImpossiBLE.dylib:$out/libSimLink-ios.dylib ;;
	watch) dev=$WATCH; id=$WATCH_ID; lib=$out/impossible/libImpossiBLE-watch.dylib:$out/libSimLink-watch.dylib ;;
	*) echo "launch phone|watch" >&2; exit 2 ;;
	esac
	xcrun simctl terminate "$dev" "$id" 2>/dev/null || true
	SIMCTL_CHILD_DYLD_INSERT_LIBRARIES=$lib SIMCTL_CHILD_SIMLINK_FILE=$LINK SIMCTL_CHILD_SIMLINK_QUEUE=$SIMLINK_QUEUE \
		xcrun simctl launch "$dev" "$id"
}

quit() {
	case "$1" in
	phone) xcrun simctl terminate "$PHONE" "$PHONE_ID" ;;
	watch) xcrun simctl terminate "$WATCH" "$WATCH_ID" ;;
	*) echo "quit phone|watch" >&2; exit 2 ;;
	esac
}

range() { # app|provider value in(0|1)
	curl -s -m 3 -X POST "localhost${MUX_API}/range?$1=$2&in=$3"; echo
}

# The phone and the watch are parted while the phone is away or the watch is off (the paired
# Simulators keep reporting a shut-down watch as reachable).
link() {
	mkdir -p "$run"
	if [ -e "$run/phone-away" ] || [ -e "$run/watch-off" ]; then echo down >"$LINK"; else rm -f "$LINK"; fi
}

phone() {
	case "$1" in
	away) mkdir -p "$run"; touch "$run/phone-away"; link; range app "$PHONE_ID" 0 ;;
	back) rm -f "$run/phone-away"; link; range app "$PHONE_ID" 1 ;;
	*) echo "phone away|back" >&2; exit 2 ;;
	esac
}

pod() {
	case "$1" in
	away) range provider pod 0 ;;
	back) range provider pod 1 ;;
	*) echo "pod away|back" >&2; exit 2 ;;
	esac
}

watch() {
	need_sims
	case "$1" in
	off) xcrun simctl shutdown "$WATCH"; mkdir -p "$run"; touch "$run/watch-off"; link
		# A UI driver on the watch ends with it; ui.sh attaches a new one at its next command.
		[ -f /tmp/sportmode-ui/watch.pid ] && kill "$(cat /tmp/sportmode-ui/watch.pid)" 2>/dev/null || true ;;
	# The link comes up with the watch app, not with the watch: the paired Simulators accept a live
	# message for an app not yet running and lose it, where a device would fail it to the queue.
	on) xcrun simctl boot "$WATCH" 2>/dev/null || true
		xcrun simctl bootstatus "$WATCH" -b >/dev/null; launch watch; rm -f "$run/watch-off"; link ;;
	*) echo "watch off|on" >&2; exit 2 ;;
	esac
}

# Sport Mode's own log files in each app's Documents.
applog() { # phone|watch
	case "$1" in
	phone) c=$(xcrun simctl get_app_container "$PHONE" "$PHONE_ID" data); echo "$c/Documents/g7phone-latest.log" ;;
	watch) c=$(xcrun simctl get_app_container "$WATCH" "$WATCH_ID" data); echo "$c/Documents/g7watch.log" ;;
	esac
}

logof() {
	case "$1" in
	phone | watch) tail -n "${2:-40}" "$(applog "$1")" ;;
	pod) tail -n "${2:-40}" "$run/pod.log" ;;
	g7) tail -n "${2:-40}" "$run/g7.log" ;;
	mux) tail -n "${2:-40}" "$run/mux.log" ;;
	*) echo "log phone|watch|pod|g7|mux [lines]" >&2; exit 2 ;;
	esac
}

# Sourced by ui.sh for the settings and helpers above.
[ -n "${SIM_SOURCED:-}" ] && return 0

case "${1:-}" in
build) build ;;
sims) sims ;;
apps) apps ;;
install) install ;;
start) start "${2:-}" ;;
stop) stop ;;
status) status ;;
launch) launch "${2:-}" ;;
log) logof "${2:-}" "${3:-}" ;;
applog) applog "${2:-}" ;;
bundle) case "${2:-}" in phone) echo "$PHONE_ID" ;; watch) echo "$WATCH_ID" ;; *) exit 2 ;; esac ;;
quit) quit "${2:-}" ;;
since) f=$(applog "${2:-}"); awk -v t="${3:-00:00:00}" '$2 >= t' "$f" | grep -E "${4:-.}" | cut -c12-260 ;;
phone) phone "${2:-}" ;;
pod) pod "${2:-}" ;;
watch) watch "${2:-}" ;;
range) curl -s -m 3 "localhost${MUX_API}/range"; echo; [ -f "$LINK" ] && echo "link: $(cat "$LINK")" || echo "link: up" ;;
*) sed -n 2,27p "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
