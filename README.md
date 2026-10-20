# Sport Mode in the Simulators

Runs Loop's Sport Mode with no devices: the phone app and the watch app in a paired pair of
Simulators, a simulated pod and a simulated sensor on the Mac. The Sport Mode bench tests run here,
with the phone and the watch going out of reach, the watch shutting down and the pod going out of
reach all done by commands. [TESTS.md](TESTS.md) has each test's steps.

It is built on LoopKit's pod simulator and G7 simulator and the ImpossiBLE Bluetooth shim, with
changes proposed back to each ([PR-DRAFTS.md](PR-DRAFTS.md)):

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

`WORKSPACE` is a LoopWorkspace checkout with Sport Mode: `jeremybarnum/LoopWorkspace` branch
`SportMode-bench`. Two things on the Loop side that a run needs:
- A watch bolus is confirmed by turning the crown, which the Simulator has none of. The bench branch
  confirms it with a double tap in Simulator builds only.
- In the Simulator, OmnipodKit faked some pod operations whenever it ran there, even with the simulated
  pod. With the fix, it fakes them only when there is no simulated pod. The fix is not yet on the branch;
  without it, a hand-back's temp cancel sends nothing to the pod.

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
./ui.sh watch double "Turn Digital"     # confirms a watch bolus (the bench's double tap)
./ui.sh phone systype '0000\n'          # the passcode a phone bolus asks for
```

A driver attaches in 10–17 s and restarts by itself after `watch off`; a tap takes under a second.
The crown cannot be turned from a test in the Simulator for Loop's bolus confirmation, so the bench's
double tap stays. A step whose screen changes under it (a sheet closing) can end the driver; the next
command attaches a new one.

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
