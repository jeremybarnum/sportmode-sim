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

Needs Xcode with the iOS and watchOS Simulator runtimes, and Go. Then:

```sh
./sim.sh build        # clones and builds the simulators, the mux and the libraries into build/
./sim.sh sims         # creates and pairs "Sport Mode Phone" and "Sport Mode Watch" (ids in .sims)
WORKSPACE=~/src/LoopWorkspace ./sim.sh apps   # builds Loop's phone and watch apps for them
./sim.sh install
./sim.sh start -fresh # a new pod and sensor
./sim.sh launch phone
```

`WORKSPACE` is a LoopWorkspace checkout with Sport Mode, branch `sim-testing` of
`jeremybarnum/LoopWorkspace` (`git clone --recurse-submodules -b sim-testing …`). It is Sport Mode's
build with two changes for the Simulator only:
- A watch bolus is confirmed by turning the crown, which a test cannot do on that screen in the
  Simulator; a double tap confirms it in Simulator builds.
- OmnipodKit fakes pod operations in the Simulator only when no simulated pod answers. Without this, a
  hand-back's temp cancel would send nothing to the simulated pod.

**Onboard the phone once** (the Simulators keep it): long-press the logo on Welcome to skip the setup,
then in Settings add the G7 sensor (code 4321) and the Omnipod DASH pod (pair, prime, insert). A bolus
on the phone asks the Simulator's passcode: 0000. Then `./sim.sh launch watch`, and before the first
Start wait for the watch to read the sensor and log `dormant grant refreshed`.

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

Scripted: T1, T3–T11, T13, T16–T19. T9's six hours are simulated by aging the watch's saved last pod
reading while it is off. Not scripted: T2 (no way to cause it), T12 (opportunistic), T14 (a tap
within a second of the watch waking), T15 (a clarifying test for the hardware emulator).

A fresh watch app gets the phone's standing copy (for an offline start) only after its first
normal Start, so run a test with a normal Start (T1 or T3) before T6, T7, T10, T13 and T19;
`run.sh` with no argument runs them in number order, which does that.

## Faster runs

`TIME_SCALE=5 ./sim.sh start`, then `./sim.sh launch phone` and `launch watch`: the sensor reads every
60 s instead of 300, and the apps, launched with `SPORTMODE_TIME_SCALE=5`, divide their own waits by
5: the watch's report overdue (6 min → 72 s), the take-back's settle, the standing copy's refresh,
and Loop's 4.2-minute loop rate limit on both phone and watch. Timestamps are real; only waits
shrink. Not scaled, because they are real latencies: the 10 s and 30 s answer waits, the 60 s
takeover lease, resend throttles. The scale needs a Loop built from a branch that has it
(`sim-testing` does); without it the apps run at real time and only the sensor is faster. Use one
scale for a sensor's whole life: restarting the sensor simulator at another interval re-indexes
its readings.

## What it does not cover

- Without `ui.sh`, taps go through the Simulator window; the first tap after a page change or after the
  watch wakes is often swallowed: check the log and tap again.
- A backgrounded app is not woken by simulated Bluetooth, so a locked phone (T16) and the watch app's
  background life are not reproduced. The G7 simulator's suspender would do it, one per app.
- No clock control: T9 (6 hours) needs a real wait.
- The paired Simulators' reachability is not a device's; `sim.sh` and SimLink correct the known
  differences (a shut-down watch reads reachable; a live message to a watch app not yet running is lost).
- The pod simulator does not filter scans by service.

A full pass of the runnable tests takes about three hours, most of it waiting on 5-minute readings.
