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
#   sim.sh watch away|back  the pod and sensor out of the watch's reach (the phone still linked)
#   sim.sh pod slow <s>     the pod's next state-changing command waits <s> before it is accepted
#   sim.sh link slow <s>|normal  each live phone–watch message arrives <s> late, or on time again
#   sim.sh link down|up     the phone–watch link alone cut, each still in reach of the pod and sensor
#   sim.sh glucose <mg/dL>|walk <mg/dL>|sine <mg/dL> <amplitude>  what the sensor reads from now on
#   sim.sh phone radio-off|radio-on  Bluetooth off on the phone (it reads powered off), the watch link up
#   sim.sh watch off|on     shut the watch Simulator down; boot it and launch the watch app
#   sim.sh quit phone|watch end the app (a force quit)
#   sim.sh range            what is out of range now
#
# Environment: TIME_SCALE=N (faster runs: readings every 300/N s and the apps' waits divided by N;
# set at `start` and kept for `launch`), PHONE_SIM, WATCH_SIM (Simulator UDIDs; default: the pair
# `sims` made; zsh keeps WATCH for itself), WORKSPACE (a
# LoopWorkspace checkout, for `apps`), APPS (a Build/Products directory, default build/dd's),
# MUX_TRACE=1 (the mux logs every request and event for a peripheral), RIG=<name> (a second rig,
# with its own Simulator pair in .sims-<name>, apps in build/dd-<name>, and
# pod and sensor state in build/run-<name>; settings such as DEXCOM_APP=1 can go in .sims-<name>; rigs
# run at the same time only in different slots, SLOT=<n> in their .sims-<name>, each with its own
# sockets, ports and files: see rig.sh), CONNECT_DELAY=<duration> (at `start`: how long each Bluetooth connect
# takes, as over a radio; 1500ms by default, 0 for at once), DEXCOM_APP=1 (at `start`:
# the simulated G7 also plays the Dexcom app, for a build whose G7 code does not authenticate itself
# and rides the Dexcom app's link, as stock G7SensorKit does).
set -eu

here=$(cd "$(dirname "$0")" && pwd)
out=$here/build
RIG=${RIG:-}
run=$out/run${RIG:+-$RIG}
sims_file=$here/.sims${RIG:+-$RIG}

# The simulators, at the commits this harness was tested with (LoopKit/g7sim and LoopKit/pod with
# the changes proposed upstream; g7sim builds ImpossiBLE with its own patches).
G7SIM=https://github.com/jeremybarnum/g7sim; G7SIM_COMMIT=ee2a13b
POD=https://github.com/jeremybarnum/pod;     POD_COMMIT=3823843

[ -f "$sims_file" ] && . "$sims_file"
# POD_SIM (in a rig's .sims): another pod simulator build for that rig, such as one with a change
# proposed upstream; the others keep build/pod-sim.
POD_SIM=${POD_SIM:-$out/pod-sim}
PHONE=${PHONE_SIM:-${SIMS_PHONE:-}}
WATCH=${WATCH_SIM:-${SIMS_WATCH:-}}
APPS=${APPS:-$out/dd${RIG:+-$RIG}/Build/Products}
PHONE_APP=$APPS/Debug-iphonesimulator/Loop.app
WATCH_APP=$APPS/Debug-watchsimulator/WatchApp.app
. "$here/rig.sh"

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

# ImpossiBLE's simulator library, as g7sim's build-impossible.sh compiles it.
build_impossible() { # sdk target out
	src=$out/impossible/ImpossiBLE
	xcrun -sdk "$1" clang -dynamiclib -fobjc-arc -fmodules -target "$2" \
		-I "$src/Sources/ImpossiBLE/include" -I "$src/Sources/ImpossiBLE" \
		-framework Foundation -framework CoreBluetooth -install_name @rpath/libImpossiBLE.dylib \
		"$src"/Sources/ImpossiBLE/*.m -o "$out/impossible/$3"
}

build() {
	mkdir -p "$out" "$run"
	clone $G7SIM $G7SIM_COMMIT "$out/g7sim"
	clone $POD $POD_COMMIT "$out/pod"
	# ImpossiBLE for the iOS and watchOS Simulators, with g7sim's fixes, then this harness's own
	# (impossible-patches: the socket from the app's environment, for rigs in different slots).
	"$out/g7sim/simulator/build-impossible.sh" "$out/impossible" >/dev/null
	for patch in "$here"/impossible-patches/*.patch; do git -C "$out/impossible/ImpossiBLE" apply "$patch"; done
	build_impossible iphonesimulator arm64-apple-ios15.0-simulator libImpossiBLE.dylib
	build_impossible watchsimulator arm64-apple-watchos10.0-simulator libImpossiBLE-watch.dylib
	echo "built ImpossiBLE (iOS, watchOS)"
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
	p=$(xcrun simctl create "Sport Mode Phone${RIG:+ ($RIG)}" "$pt" "$pr")
	w=$(xcrun simctl create "Sport Mode Watch${RIG:+ ($RIG)}" "$wt" "$wr")
	xcrun simctl pair "$w" "$p" >/dev/null
	printf 'SIMS_PHONE=%s\nSIMS_WATCH=%s\n' "$p" "$w" >"$sims_file"
	# The phone fully up before the watch: booted together on a slow machine, the pair can stay
	# "(active, disconnected)", and the phone never sees the watch app.
	xcrun simctl boot "$p"; xcrun simctl bootstatus "$p" -b >/dev/null; xcrun simctl boot "$w"
	echo "phone $p, watch $w (saved in $(basename "$sims_file"))"
}

# Whether this slot's copy of a simulator or the mux runs: each is told by its API port.
started() {
	case "$1" in pod-sim) api=$POD_API ;; g7-sim) api=$G7_API ;; impossible-mux) api=$MUX_API ;; esac
	pgrep -f "$(binary $1) .*-api $api( |\$)" >/dev/null 2>&1
}
binary() { case "$1" in pod-sim) echo "$POD_SIM" ;; *) echo "$out/$1" ;; esac; }
active_file=$out/active-rig; [ "$SLOT" = 0 ] || active_file=$out/active-rig-$SLOT

# Whether the slot's ports are free of simulators this checkout did not start: another checkout's rig
# in the same slot shares its ports and sockets, and `started` cannot see it.
slot_free() {
	for p in pod-sim:$POD_API g7-sim:$G7_API impossible-mux:$MUX_API; do
		started "${p%%:*}" && continue
		if lsof -nP -iTCP"${p#*:}" -sTCP:LISTEN >/dev/null 2>&1; then
			echo "port ${p#*::} of slot $SLOT is held by a rig this checkout did not start ($(lsof -nP -iTCP"${p#*:}" -sTCP:LISTEN -Fn -Fp 2>/dev/null | sed -n 's/^p//p' | head -1 | xargs -I{} ps -o command= -p {} | cut -c1-80)): use another SLOT, or stop that rig" >&2
			return 1
		fi
	done
}

# A simulator's earlier log is kept beside the new one when it starts, the five newest of each, so a
# run's evidence survives the next start.
keep_log() { # pod|g7|mux
	[ -s "$run/$1.log" ] || return 0
	mv "$run/$1.log" "$run/$1-$(date +%Y%m%d-%H%M%S).log"
	ls -t "$run/$1"-2*.log 2>/dev/null | tail -n +6 | while read -r f; do rm -f "$f"; done
}

start() {
	# A slot's simulators serve one rig at a time.
	active=$(cat "$active_file" 2>/dev/null || true)
	if [ "${active:-bench}" != "${RIG:-bench}" ] && { started pod-sim || started g7-sim || started impossible-mux; }; then
		echo "the ${active:-bench} rig's simulators are running in slot $SLOT: 'sim.sh stop' first" >&2; exit 2
	fi
	slot_free || exit 2
	mkdir -p "$out"; echo "${RIG:-bench}" >"$active_file"
	fresh=${1:-}
	podfresh=$fresh; [ "$fresh" = -fresh-pod ] && { fresh=; podfresh=-fresh; }
	mkdir -p "$run"
	# A faster clock: the sensor reads every 300/N s, and the apps (launched with the same N)
	# divide their own waits by it. Kept with the run so launch agrees with start.
	# A sensor's reading interval is fixed for its life: at another scale a saved sensor serves no new
	# readings, so a scale change starts a new one.
	scale=${TIME_SCALE:-1}; was=$(cat "$run/time-scale" 2>/dev/null || true); echo "$scale" >"$run/time-scale"
	if [ -n "$was" ] && [ "$was" != "$scale" ] && [ -z "$fresh" ] && ! started g7-sim; then
		echo "time scale $was → $scale: a new sensor"; fresh=-fresh
	fi
	interval=; [ "$scale" -gt 1 ] 2>/dev/null && interval="-interval $((300 / scale))s"
	started pod-sim || { keep_log pod; nohup "$POD_SIM" -transport impossible -socket $POD_SOCK -api $POD_API \
		-state "$run/pod-state.toml" ${podfresh:+-fresh} >"$run/pod.log" 2>&1 & }
	# The stand-in sensor G7SensorKit offers in the Simulator, so "scan" and manual entry both find it.
	# In a subshell for its working directory, which exec hands to the simulator, so nothing is left
	# holding the terminal.
	started g7-sim || { keep_log g7; (cd "$run" && exec nohup "$out/g7-sim" -transport impossible -socket $G7_SOCK -api $G7_API \
		$interval ${DEXCOM_APP:+-dexcom-app} ${fresh:+-fresh -code 4321 -serial 7810293746}) >"$run/g7.log" 2>&1 </dev/null & }
	sleep 1
	# The mux refuses the socket if another provider (ImpossiBLE's menu bar app?) holds it; its log says.
	# A radio takes time to bring a link up; at once, an app that launches beside its pod connects
	# before it has finished starting.
	started impossible-mux || { keep_log mux; nohup "$out/impossible-mux" -api $MUX_API -socket $APP_SOCK -connect-delay "${CONNECT_DELAY:-1500ms}" $G7_SOCK $POD_SOCK >"$run/mux.log" 2>&1 & }
	sleep 1
	status
	started impossible-mux || { tail -2 "$run/mux.log"; exit 1; }
}

stop() {
	for p in impossible-mux pod-sim g7-sim; do
		case "$p" in pod-sim) api=$POD_API ;; g7-sim) api=$G7_API ;; impossible-mux) api=$MUX_API ;; esac
		pkill -f "$(binary $p) .*-api $api( |\$)" 2>/dev/null && echo "stopped $p" || true
	done
	rm -f $APP_SOCK $POD_SOCK $G7_SOCK
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
	# A Simulator that is shut down (a Mac restart, or a driver that booted it and ended) boots first.
	xcrun simctl bootstatus "$dev" -b >/dev/null 2>&1 || true
	xcrun simctl terminate "$dev" "$id" 2>/dev/null || true
	[ "$1" = phone ] && keep_phone_log
	scale=${TIME_SCALE:-$(cat "$run/time-scale" 2>/dev/null || echo 1)}
	SIMCTL_CHILD_DYLD_INSERT_LIBRARIES=$lib SIMCTL_CHILD_IMPOSSIBLE_SOCKET=$APP_SOCK \
		SIMCTL_CHILD_SIMLINK_FILE=$LINK SIMCTL_CHILD_SIMLINK_QUEUE=$SIMLINK_QUEUE \
		SIMCTL_CHILD_SPORTMODE_TIME_SCALE=$scale xcrun simctl launch "$dev" "$id"
}

# A phone log that starts again at each launch (a build that keeps only the latest) is kept
# here first, once, so a test's window survives the relaunches it makes.
keep_phone_log() {
	local f head
	mkdir -p "$run"
	f=$(applog phone 2>/dev/null) || return 0
	[ -s "$f" ] || return 0
	case "$(basename "$f")" in *latest*) ;; *) return 0 ;; esac
	head=$(head -1 "$f")
	[ "$head" = "$(cat "$run/phone-log-kept" 2>/dev/null)" ] && return 0
	cat "$f" >>"$run/phone-earlier.log"
	echo "$head" >"$run/phone-log-kept"
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

power() { # app on(0|1)
	curl -s -m 3 -X POST "localhost${MUX_API}/power?app=$1&on=$2"; echo
}

# The phone and the watch are parted while the phone is away or the watch is off (the paired
# Simulators keep reporting a shut-down watch as reachable).
link() {
	mkdir -p "$run"
	if [ -e "$run/phone-away" ] || [ -e "$run/watch-off" ] || [ -e "$run/link-down" ]; then echo down >"$LINK"
	elif [ -s "$run/link-slow" ]; then echo "slow $(cat "$run/link-slow")" >"$LINK"
	else rm -f "$LINK"; fi
}

# A sluggish link: each live message arrives N seconds late (still reachable), or on time again.
linkcmd() {
	case "$1" in
	slow) mkdir -p "$run"; echo "${2:-4}" >"$run/link-slow"; link; echo "link: live messages ${2:-4} s late" ;;
	normal) rm -f "$run/link-slow"; link; echo "link: live messages on time" ;;
	down) mkdir -p "$run"; touch "$run/link-down"; link; echo "link: down (phone and watch each still in reach of the pod and sensor)" ;;
	up) rm -f "$run/link-down"; link; echo "link: up" ;;
	*) echo "link slow <s>|normal|down|up" >&2; exit 2 ;;
	esac
}

phone() {
	case "$1" in
	away) mkdir -p "$run"; touch "$run/phone-away"; link; range app "$PHONE_ID" 0 ;;
	back) rm -f "$run/phone-away"; link; range app "$PHONE_ID" 1; [ -e "$run/phone-radio-off" ] && { rm -f "$run/phone-radio-off"; power "$PHONE_ID" 1; } || true ;;
	# Bluetooth off on the phone: out of reach of the pod and sensor, while the watch link stays
	# up (as over Wi-Fi).
	radio-off) mkdir -p "$run"; touch "$run/phone-radio-off"; power "$PHONE_ID" 0 ;;
	radio-on) rm -f "$run/phone-radio-off"; power "$PHONE_ID" 1; [ -e "$run/phone-away" ] && range app "$PHONE_ID" 0 || true ;;
	*) echo "phone away|back|radio-off|radio-on" >&2; exit 2 ;;
	esac
}

pod() {
	case "$1" in
	away) range provider pod 0 ;;
	back) range provider pod 1 ;;
	# The pod's next state-changing command waits this long before the pod acts on it and answers,
	# as a pod slow to accept: the app has sent it and does not yet know it took.
	slow) curl -s -m 3 -X POST "localhost${POD_API}/command" -d "{\"command\":\"slowNextCommand\",\"value\":${2:-5}}"; echo "pod: next command held ${2:-5} s" ;;
	*) echo "pod away|back|slow <seconds>" >&2; exit 2 ;;
	esac
}

watch() {
	need_sims
	case "$1" in
	off) xcrun simctl shutdown "$WATCH"; mkdir -p "$run"; touch "$run/watch-off"; link
		# A UI driver on the watch ends with it; ui.sh attaches a new one at its next command.
		[ -f "$SPORTMODE_UI/watch.pid" ] && kill "$(cat "$SPORTMODE_UI/watch.pid")" 2>/dev/null || true ;;
	# The link comes up with the watch app, not with the watch: the paired Simulators accept a live
	# message for an app not yet running and lose it, where a device would fail it to the queue.
	# The relay keys a watch app's range on the name its Bluetooth client registers: the extension's on
	# an extension-based watch app (production), the app's own on a single-target one (next-dev). Both
	# are set; the one the relay does not know matches nothing.
	away) mkdir -p "$run"; touch "$run/watch-away"; range app "$WATCH_ID" 0; range app "$WATCH_ID.watchkitextension" 0 ;;
	back) rm -f "$run/watch-away"; range app "$WATCH_ID" 1; range app "$WATCH_ID.watchkitextension" 1 ;;
	on) xcrun simctl boot "$WATCH" 2>/dev/null || true
		xcrun simctl bootstatus "$WATCH" -b >/dev/null; launch watch; rm -f "$run/watch-off"; link
		# After the watch Simulator reboots, the phone app's queued transfers from the watch stop
		# arriving until the phone app is restarted (a Simulator quirk): the next reset does it.
		touch "$run/watch-rebooted" ;;
	*) echo "watch off|on|away|back" >&2; exit 2 ;;
	esac
}

# An app's data container: from simctl while its Simulator runs, else found on disk by its bundle id,
# so the logs of a Simulator that is shut down can still be read.
container() { # device bundle-id
	[ -n "$2" ] || return 1
	xcrun simctl get_app_container "$1" "$2" data 2>/dev/null && return 0
	for d in "$HOME/Library/Developer/CoreSimulator/Devices/$1/data/Containers/Data"/*/*; do
		[ "$(plutil -extract MCMMetadataIdentifier raw "$d/.com.apple.mobile_container_manager.metadata.plist" 2>/dev/null)" = "$2" ] \
			&& { echo "$d"; return 0; }
	done
	return 1
}

# Sport Mode's own log files in each app's Documents.
applog() { # phone|watch
	case "$1" in
	phone) echo "$(container "$PHONE" "$PHONE_ID")/Documents/g7phone-latest.log" ;;
	watch)
		# A WatchKit extension keeps its own container, beside the app's.
		for id in "$WATCH_ID" "$WATCH_ID.watchkitextension"; do
			f=$(container "$WATCH" "$id")/Documents/g7watch.log; [ -f "$f" ] && break
		done
		echo "$f" ;;
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
podapi) echo "$POD_API" ;;
quit) quit "${2:-}" ;;
since)
	# A time of day more than an hour after now is yesterday's: a window that crosses midnight keeps
	# its lines (a time a moment ahead of the clock is still today's).
	f=$(applog "${2:-}"); t=${3:-00:00:00}; day=$(date +%F)
	if [ "$(echo "${t%%.*} $(date +%T)" | awk '{ split($1, a, ":"); split($2, b, ":"); print (a[1]*3600 + a[2]*60 + a[3]) - (b[1]*3600 + b[2]*60 + b[3]) }')" -gt 3600 ]; then
		day=$(date -v-1d +%F)
	fi
	# The phone's earlier launches first, as kept at each relaunch.
	k=; [ "$2" = phone ] && [ -f "$run/phone-earlier.log" ] && k=$run/phone-earlier.log
	awk -v t="$day $t" '($1 " " $2) >= t' $k "$f" | grep -E "${4:-.}" | cut -c12-260 ;;
phone) phone "${2:-}" ;;
pod) pod "${2:-}" "${3:-}" ;;
watch) watch "${2:-}" ;;
link) linkcmd "${2:-}" "${3:-}" ;;
range) curl -s -m 3 "localhost${MUX_API}/range"; echo; [ -f "$LINK" ] && echo "link: $(cat "$LINK")" || echo "link: up" ;;
glucose)
	case "${2:-}" in
	walk) body="{\"kind\":\"walk\",\"value\":${3:-120}}" ;;
	sine) body="{\"kind\":\"sine\",\"value\":${3:-120},\"amplitude\":${4:-30}}" ;;
	[0-9]*) body="{\"kind\":\"fixed\",\"value\":$2}" ;;
	*) echo "glucose <mg/dL>|walk <mg/dL>|sine <mg/dL> <amplitude>" >&2; exit 2 ;;
	esac
	curl -s -m 3 -X POST "localhost${G7_API}/glucose" -d "$body" >/dev/null && echo "glucose: $body" ;;
*) sed -n 2,27p "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
