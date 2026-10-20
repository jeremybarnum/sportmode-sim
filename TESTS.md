# The Sport Mode bench tests in the Simulators

Each bench test with its Simulator steps. The rows of the control table they check are in
`Documentation/SportMode/Control.md` in the Loop repository. A tap means the Simulator window;
`sim.sh` is this repository's driver. After a test, `./check.sh T<n> <start time>` prints the lines
that decide it from both apps' logs.

Situations: **phone away** = `sim.sh phone away` (the phone out of reach of the watch, the pod and the
sensor), **watch off** = `sim.sh watch off` (the watch shut down; `watch on` boots it and opens the app),
**pod away** = `sim.sh pod away`. Sensor readings come every 5 minutes; `sim.sh log g7 3` shows the last.

| Test | What it proves | Simulator |
|---|---|---|
| T1 | Ordinary loan, ended on the watch: takeover, hand-back, insulin check clean, the watch's temp ended | Runs |
| T2 | A hand-back that arrives without a pod reading still ends the watch's temp | No way to cause it; look for it in any run |
| T3 | Phone take-back: the phone takes the pod first, then stops the watch | Runs |
| T4 | Take-back with the watch's records missing: the insulin is estimated once, then retired by the records | Runs (the watch app opens at boot, not in the background) |
| T5 | Take-back with the pod out of reach: refused with a message, nothing changes | Runs |
| T6 | Offline start, phone back: the phone adopts the loan, check clean | Runs |
| T7 | Offline start, watch bolus, phone back first: the phone books the insulin, the watch's records replace it | Runs |
| T8 | Watch app restarts during a loan: a resume check before the first cycle | Runs |
| T9 | Watch off longer than 6 hours: no resume, records go home | Not run: the Simulators use the Mac's clock |
| T10 | When the offline start is offered (at once, during the wait, after 10 s) | Runs |
| T11 | A carb deleted on the watch reaches the phone | Runs (Loop's own entries; the Simulator has no Health entries to check) |
| T12 | The status screen header survives a rotation around a loan | Opportunistic |
| T13 | A Start after an offline start that failed at the takeover | Runs |
| T14 | A Start within a second of the watch app waking | Not run: the first tap after the app comes back is swallowed |
| T15 | Clarifying: emulator or phone at fault | Not applicable |
| T16 | The phone asks a silent watch and takes the pod back itself | Runs with the phone app in front: a background app is not woken by simulated Bluetooth |
| T17 | A watch back from off asks before looping; the phone stands it aside | Runs |
| T18 | End on the watch with the phone away: refused on screen after 10 s, loan continues | Runs |
| T19 | A revived watch's claim to a loan older than the phone's takeover is refused | Runs |

## Steps

**T1.** Tap Start on the watch. Let two readings pass. Tap End on the watch.
Pass: phone `reconcile[AUTHORITATIVE]` within ±0.20 U and `temp cancelled`; watch `ACTIVE`, `[odometer] (own)`
within ±0.20 U at each reading, `hand-back`, `ack RECEIVED`; no watch `BOOKED`.

**T2.** In any run, the watch logging `drain GIVING UP` or `staying RELEASED`. Pass: phone `reclaim VERIFIED`, then
`temp cancelled`, with no `reconcile[` between them.

**T3.** During a loan, on the phone tap the pod tile and take the pod back.
Pass within about 5 s: phone `take-back: pod link up`, `revoke`, `reconcile[FORCE-RECLAIM]`, `temp cancelled`; the
watch closes the loan.

**T4.** Start on the watch, one cycle. `phone away`. Bolus 0.5 U on the watch (confirm with a double tap) and wait for
the pod to accept it. `watch off`. `phone back`. Take the pod back on the phone. Wait one reading. `watch on`.
Pass: phone `reconcile[FORCE-RECLAIM]` near the bolus, one `estimate BOOKED`; next reading `[odometer] (own)` near
zero and no second booking; watch `RESUMED`, the stop received before any `dosemath`; phone `estimate RETIRED`
when the records arrive.

**T5.** During a loan, `pod away`, take back on the phone. `pod back`, take back again.
Pass: first `take-back REFUSED — no pod link …; loan unchanged`, "Couldn't Reach the Pod"; then as T3.

**T6.** `phone away`. Start on the watch, Start Anyway. Two readings. `phone back`. End on the watch.
Pass: watch `SEIZE confirmed`, `seized loan ACTIVE`; phone `[seize] RETRO-ACK`,
`reconcile[AUTHORITATIVE]` within ±0.20 U, `temp cancelled`.

**T7.** `phone away`. Offline start on the watch; bolus 0.5 U on the watch. Short: wait 3 minutes, `phone back`,
End on the watch. Full: `watch off` after the bolus, `phone back`, wait one reading, `watch on`, End on
the watch. Pass: phone `estimate BOOKED` at its first reading if it reads the pod before it hears from the watch
(standing aside and booking nothing is also right); next reading near zero; at the hand-back `RETRO-ACK`, `estimate
RETIRED`, final check within ±0.20 U.

**T8.** During a loan, `quit watch` then `launch watch` (or `watch off`, `watch on`). Booking case: with the watch
off, take the pod back on the phone and bolus on the phone (passcode 0000), then `watch on`.
Pass: watch `RESUMED`, then at its first pod report `[odometer] (own)` within ±0.20 U or `BOOKED`, with no
`dosemath` or `enacting` before it.

**T10.** (a) `phone away`, tap Start. (b) Tap Start, `phone away` within 10 s. (c) `quit phone`, tap Start.
Pass: watch (a) `offline start offered now` at the tap; (b) `phone went out of reach during the request`;
(c) `REQUEST TIMED OUT … offering offline start` about 10 s after the tap.

**T11.** Add carbs on the phone. Start a loan. Delete the entry on the watch. End.
Pass: phone `carb DELETE from wrist`, `carb DELETE applied on phone`; the entry gone from the phone's list.

**T13.** `pod away`, `phone away`. Start on the watch, Start Anyway; the takeover fails after about 3 minutes
(`TAKEOVER FAILED`). `pod back`, `phone back`; wait for the phone to read the pod. Normal Start on the watch.
Pass: phone `GRANT` numbered above the watch's loan; watch `GRANT received`, `ACTIVE`, no `grant REJECTED`.

**T16.** Start on the watch; bolus 0.5 U on the watch. `watch off`. Keep the phone app in front; touch nothing for
about 12 minutes. Pass: phone `asking the watch whether it holds the pod`, about 10 s later `the watch did NOT answer —
taking the pod back`, `take-back: pod link up`, `reconcile[FORCE-RECLAIM]` booking about 0.5 U, `temp cancelled`,
"Watch Not Responding".

**T17.** Start on the watch, one cycle. `watch off`. Take the pod back on the phone and bolus 0.5 U on the phone
(passcode 0000). `watch on`. Pass: watch `RESUMED`, `statusReport sent … asking the phone before looping`, `RX
revoke`, `REVOKED`, no `dosemath` between `RESUMED` and the revoke.

**T18.** During a loan, `phone away`. Tap End on the watch. Pass: about 10 s later `HAND-BACK not possible`, the
message on screen, the loan continues. `phone back`, End again: a clean hand-back.

**T19.** `phone away`. Offline start on the watch; bolus 0.5 U; `watch off`. `phone back` with the phone app in front:
at its first reading the phone books the insulin and keeps the pod. `watch on`. Pass: phone `no answer from the watch
… keeps the pod`, then `a revived watch's claim to a loan started before this phone took over … revoke`; watch
`RESUMED`, "Checking with your iPhone…", `REVOKED`, no `dosemath` between.
