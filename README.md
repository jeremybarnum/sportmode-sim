# Sport Mode in the Simulators

Runs Loop's Sport Mode with no devices: the phone app and the watch app in a paired pair of
Simulators, a simulated pod and a simulated sensor on the Mac. The Sport Mode bench tests run here,
with the phone and the watch going out of reach, the watch shutting down and the pod going out of
reach all done by commands. [TESTS.md](TESTS.md) has each test's steps.

It is built on LoopKit's pod simulator and G7 simulator and the ImpossiBLE Bluetooth shim, with
changes to each, on these forks:

| Piece | What it adds | Where |
|---|---|---|
| ImpossiBLE | The shim built for the watchOS Simulator too; a reconnect made inside didDisconnect keeps its app | `jeremybarnum/ImpossiBLE` `keep-owner-on-reconnect`; g7sim carries it as patch 0007 |
| impossible-mux (in g7sim) | Several apps at once: one holds a peripheral, the others' connects wait for it, as over the air; an out-of-range switch per app and per simulator | `jeremybarnum/g7sim` `multi-app` |
| G7 simulator | The phone and the watch are each a display of their own behind the mux | same branch |
| Pod simulator | Insulin delivered over time, as a pod does: basal by the schedule, temps, a bolus pulse by pulse | `jeremybarnum/pod` `delivery-over-time` |
| SimLink (here) | Parts the phone and the watch on command, and carries WatchConnectivity's queued transfers, which the paired Simulators deliver only when an app launches | `SimLink.m` |

## Setup

Needs a Mac with Xcode and its iOS and watchOS Simulator runtimes, Go (to build the simulators and
the mux), xcodegen (`brew install xcodegen`, for the tap drivers), and a LoopWorkspace checkout of a
Sport Mode branch, for example:

```sh
git clone https://github.com/jeremybarnum/LoopWorkspace ~/src/LoopWorkspace   # tree.sh fetches the submodules
```

Then, from this repository:

```sh
./tree.sh ~/src/LoopWorkspace SportMode-bench   # the branch to test, plus the Simulator aids (below)
./sim.sh build        # clones and builds the simulators, the mux and the libraries into build/
./sim.sh sims         # creates and pairs "Sport Mode Phone" and "Sport Mode Watch" (ids in .sims)
WORKSPACE=~/src/LoopWorkspace ./sim.sh apps   # builds Loop's phone and watch apps for them
./sim.sh install
./sim.sh start -fresh # a new pod and sensor
./sim.sh launch phone
```

`tree.sh` checks out the superproject branch from the checkout's origin (or keeps the current one when
none is named) on a local branch `sim-testing`, and applies the Simulator-only aids as local commits;
nothing is pushed, and nothing of the aids reaches a device build. The aids for the next-dev line
(`aids/next-dev`) are four:
- **The watch bolus by double tap.** A watch bolus is confirmed by turning the crown, which a test cannot
  do on that screen in the Simulator; a double tap confirms it in Simulator builds.
- **OmnipodKit fakes the pod only when it is mocked.** In the Simulator it faked pod operations whenever
  it ran there, even with a simulated pod answering; then a hand-back's temp cancel sent nothing.
- **The time scale**, behind the `SIMULATED_TIME_SCALE_ENABLED` flag (see Faster runs).
- **Sport Mode on**: `SPORT_MODE_ENABLED` and the watch's entitlements (its workout session and
  time-sensitive notifications) in `LoopConfigOverride.xcconfig`.

**Onboard the phone once** (the Simulators keep it), by hand in the Simulator window or with `ui.sh`:
- On Welcome, hold the Loop logo for 3 s (2 s is not enough): setup is skipped with example settings.
  Allow Health access ("Turn On All", Allow), and close "Turn On Alarms": a Simulator app cannot have
  critical alerts, so it comes up at each launch.
- CGM: Dexcom G7, Pair Sensor, "Sensor Is On, Continue", "Enter Code by Hand": 4321, Continue; then
  Not Now for Dexcom Share.
- Pump: Omnipod, Continue, Next, Next, an insulin, Continue, Omnipod DASH, Confirm Pod Type, Pair pod;
  after priming Continue, Continue, Confirm; slide to insert the cannula, Continue, Yes, Finish Setup.
- Settings: switch Closed Loop on (the switch at the right of its row; a tap on the label does not
  toggle it), then Done. The skipped setup leaves it off, and the tests expect the loop closed.

Then `./sim.sh launch watch`, and `./sim.sh launch phone` again: the phone sees a watch app installed
after it only at its next launch (its log then shows `appInstalled=true`). Before the first Start wait
for the watch to read the sensor. A bolus on the phone asks the Simulator's passcode: 0000.

## Commands

`./sim.sh` with no argument prints them all.

| Situation | Command |
|---|---|
| Phone out of reach of everything (Bluetooth and Wi-Fi off) | `phone away`, `phone back` |
| Pod out of reach of both | `pod away`, `pod back` |
| Watch shut down | `watch off`, `watch on` (boots, opens the app, then the link comes up) |
| An app force-quit | `quit phone`, `quit watch`; `launch` to reopen |
| What is out of range | `range` |

Logs: `log phone|watch|pod|g7|mux [lines]`, `since phone|watch HH:MM:SS [regex]`, and
`./check.sh T<n> HH:MM:SS` for a test's lines. `MUX_TRACE=1 ./sim.sh start` logs every request.

## Taps without a person (trial)

`ui.sh` presses buttons in the apps by the labels on screen, through a UI test that attaches to the
running app (`ui/Driver.swift`; needs `xcodegen`). `./ui.sh build` once, then for example:

```sh
./ui.sh watch tap "Start Sport Mode"
./ui.sh watch wait 60 End
./ui.sh phone tap "Sport Mode Active" && ./ui.sh phone tap "Reclaim Now"
./ui.sh watch double "Turn Digital"     # confirms a watch bolus (the Simulator's double tap)
./ui.sh phone systype '0000\n'          # the passcode a phone bolus asks for
```

A driver attaches in 10–17 s and restarts by itself after `watch off`; a tap takes under a second.
The crown cannot be turned from a test in the Simulator for Loop's bolus confirmation, so the
double tap stays. A step whose screen changes under it (a sheet closing) can end the driver; the next
command attaches a new one.

## Tests without a person

`tests/T<n>.sh` runs a bench test start to finish: it resets to a known state (everything in range,
both apps up, no loan), does the taps and the situations, waits on the apps' logs, checks the
test's pass lines, and ends in PASS or FAIL. `tests/run.sh` runs all of them in a row (or the ones
named) and keeps each one's output under `build/results/`.

Scripted: T1, T3–T11, T13, T16–T19, T22. T9's six hours are simulated by aging the watch's saved last pod
reading while it is off. Not scripted: T2 (no way to cause it), T12 (opportunistic), T14 (a tap
within a second of the watch waking), T15 (a clarifying test for the hardware emulator).

`tests/run.sh quick` runs T1, T5 and T13, a check between review rounds that catches most breakage:
an ordinary loan (takeover, records, hand-back, audit), a take-back with the pod out of reach (settle,
verification, stop), and an offline start whose take stalls (the escalation to a scan). It took 4 min
14 s at scale 5 (T1 1:13, T5 0:35, T13 2:26). Tests named after it run too: `quick T22`. The full run
stays the gate before a pull request.

A fresh watch app gets the phone's standing copy (for an offline start) only after its first
normal Start, so run a test with a normal Start (T1 or T3) before T6, T7, T10, T13 and T19;
`run.sh` with no argument runs them in number order, which does that.

## Faster runs

`TIME_SCALE=5 ./sim.sh start`, then `./sim.sh launch phone` and `launch watch`: the sensor reads every
60 s instead of 300, and the apps, launched with `SPORTMODE_TIME_SCALE=5`, divide their own waits by
5: Loop's 4.2-minute loop rate limit on both phone and watch, the take-back's settle, the standing
copy's refresh, and the cycle part of the watch's report overdue (one cycle plus a minute's margin:
6 min at scale 1, 2 min at scale 5). Timestamps are real; only waits shrink. Not scaled, because
they are real latencies: the 10 s and 30 s answer waits, the 60 s takeover lease, resend throttles,
and the margin. A full run took 30 min at scale 5 against 49 at real time; the rest is taps,
answer waits and bolus delivery, which are real. The scale needs a Loop built from a branch that has it
(`tree.sh` adds it); without it the apps run at real time and only the sensor is faster. Use one
scale for a sensor's whole life: restarting the sensor simulator at another interval re-indexes
its readings.

## Bluetooth timing

Each Bluetooth connect takes 1.5 s, as over a radio (`CONNECT_DELAY` at `start`, `0` for at once): at once,
an app launching beside its pod connects before it has finished starting, and stock Loop then stops on a
launch-order bug that a device rarely meets.

## What it does not cover

- Without `ui.sh`, taps go through the Simulator window; the first tap after a page change or after the
  watch wakes is often swallowed: check the log and tap again.
- A backgrounded app is not woken by simulated Bluetooth, so a locked phone (T16) and the watch app's
  background life are not reproduced. The G7 simulator's suspender would do it, one per app.
- The paired Simulators' reachability is not a device's; `sim.sh` and SimLink correct the known
  differences (a shut-down watch reads reachable; a live message to a watch app not yet running is lost).
  With `SIMLINK_LIVE=1` SimLink carries the live messages as well: on a small machine (a GitHub
  runner) the paired Simulators can take minutes to deliver one while reachable reads YES. The rig
  then no longer exercises the Simulators' own live channel, only SimLink's model of a device's
  (refused payloads, a message nobody takes failing to its sender after 15 s, reply timeouts, and
  reachability: the watch reads the phone reachable while the link is up, the phone the watch while
  the watch app runs). `sim.sh link wedge` is the field's one-way wedge: reachable, each live
  message lost. `TIME_SLACK=<s>` adds to every timed check's limit, for a slow machine.
- The pod simulator does not filter scans by service.

A full pass of the scripted tests takes about 30 minutes at scale 5, 50 at real time.
