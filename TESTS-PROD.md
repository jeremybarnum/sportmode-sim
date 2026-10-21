# The production line's tests in the Simulators

The tests for the production line's next build (`prod-126`), each with its Simulator steps and the
lines that decide it. They follow that line's behaviour, which differs from the bench's: a watch app
relaunched during a loan ends the loan, a silent watch is warned about but not taken back on a timer,
and the watch reads the G7 by riding the Dexcom app's link.

The rig is `RIG=prod`: its own Simulator pair, apps built from `trees/sim-prod` (prod-126 plus the
Simulator aids), the simulated G7 playing the Dexcom app (`DEXCOM_APP=1`), and real time (the line has
no time scale). Scripts are in `tests-prod/`; `tests-prod/run.sh P1 P4` runs some, no argument runs all.
One rig runs at a time.

Setup once (done on 2026-10-20): `RIG=prod ./sim.sh sims`; build with
`RIG=prod WORKSPACE=~/Downloads/Loop/trees/sim-prod ./sim.sh apps`; `install`; `start -fresh`; on the
phone, long-press the logo on Welcome (`ui.sh phone pressxy 201 337 3`) to skip the setup, add the G7
(Dexcom G7 / ONE+, Continue), add an Omnipod DASH pod (pair, prime, insert), switch Closed Loop on.
The watch needs nothing: it adopts the sensor from the Dexcom app's next link. Its workout keepalive
asks for Health permission on the first Start, in a system sheet only a person can accept (Review,
switch on, Done).

**Pending decisions.** Tests marked *pending* touch a choice not yet ruled; they test what the code
does today and change when the ruling is built.

| Test | What it proves | State |
|---|---|---|
| P1 | Ordinary loan: takeover, the watch reads through the Dexcom app's link and loops, End, a clean audit | Scripted |
| P2 | Takeover fails with the pod out of reach: the lease runs out, takeoverFailed, the phone takes the pod back silently | *pending: 60 s lease* |
| P3 | The grant does not reach the watch: the phone's query at +20 s takes the pod back; a watch silent through the takeover: "Watch Loan Not Confirmed" at 5 min | To script |
| P4 | A Start interrupted by quitting the watch app: takeoverFailed at relaunch, the phone takes the pod back | To script |
| P5 | The watch app relaunched mid-loan ends the loan: "Sport Mode Ended", the recovered offer resent every 15 s until acknowledged, the phone takes the pod back | To script (decided: relaunch ends the loan) |
| P6 | The same with the phone unable to reach the pod (its Bluetooth off) | Needs a harness addition; *to be fixed in this build* |
| P7 | A silent watch: "Watch Not Reporting" at about 20, 40, 60 min while the phone has fresh glucose; none while it has not; no take-back on a timer | *pending: take on silence vs warn* |
| P8 | Take Back, watch live: revoke, resend at +10 s, force at +25 s if unanswered; dosing paused until the audit rules | *pending: single-path Take Back* |
| P9 | Take Back, watch silent past 330 s: force at once | *pending: single-path Take Back* |
| P10 | Take Back with the pod out of reach: "Watch Session Unverified" at 5 min, the loop opens | *pending: single-path Take Back* |
| P11 | Offline start with the phone away, then the reunion and the retro-acknowledgement | To script |
| P12 | Start with the phone unreachable waits 8 s before offering the offline start | To script |
| P13 | The watch's standing copy refreshed after an insulin and a carb entry on the phone; the status probe on the immediate channel | To script |
| P14 | A watch bolus and carbs during a loan; End refused during a watch bolus; Take Back during a bolus | To script |
| P15 | The predicted-low warning on the watch; Missed Meal Notifications off and on | Partly: needs scripted glucose |
| P16 | A hand-back that gives up: "End didn't go through" and the loan carries on | When built |

Not testable here: the workout keepalive's effect (the Simulator does not suspend apps as a watch
does), the glance asking for the wrist up, radio contention and range, watchOS ending the app in the
background, the G7 quiet window (only in the sensor's extended phase; to check whether the simulated G7
can be put there), and the phone's predicted-low and missed-meal lines (they go to the system log only).

## Steps

**P1.** Tap Start Sport Mode on the watch. Wait for a reading on the watch and a loop cycle. Tap End.
Pass: phone `GRANT — releasing pod BLE`; watch `takeover ladder start — lease +300s`, `ACTIVE — epoch`,
`connection-event CONNECT`, `INGEST src=direct-G7`, `cycle OK`, `HAND-BACK requested`, `ack RECEIVED`;
phone `offer RX … released=final`, `reclaim VERIFIED`, `reconcile[AUTHORITATIVE]` within ±0.20 U,
`R33 temp cancelled`; no `force reclaim` or `Watch Session Unverified`. The keepalive check
(`[keepalive] HKWorkoutSession(.other) started`) is reported as not made while the watch has no Health
permission.

**P2.** `sim.sh pod away`, then Start. Pass: watch `takeover read <k>/14` up to 14, then
`TAKEOVER FAILED` or `TAKEOVER ABORTED — grant lease expired`; phone
`[advert] … listen END (watch reported takeover failed …)`, then `settle:` and `reclaim VERIFIED` after
`pod back`; no notification on the phone.

**P3.** (a) Link down at the moment of the grant (`sim.sh link` cut after the phone logs `GRANT`), back
before +20 s. Pass: phone `grant unconfirmed after 20s`, watch `status query … the grant never reached
us`, phone `grant CONFIRMED LOST by the watch — reclaiming now`, watch `DENIED by phone — The hand-over
never reached the watch`. (b) The watch silent from the grant on (`watch off` after `GRANT`). Pass:
phone notification `Watch Loan Not Confirmed` at 5 min, then the settle lines 15 s later.

**P4.** Start, and quit the watch app (`sim.sh quit watch`) as the takeover begins; relaunch it.
Pass: watch `START INTERRUPTED — takeover was in flight at relaunch`, the glance note "Sport Mode start
was interrupted"; phone takes the pod back (`settle:`, `reclaim VERIFIED`).

**P5.** In a loan, quit and relaunch the watch app. Pass: watch alert `Sport Mode Ended`,
`hand-back offer attempt` resent every 15 s until acknowledged; phone `offer RX … released=final`,
`reclaim VERIFIED`, audit clean. Then the same with the phone away for a minute first: the offers queue
(`drain: iPhone UNREACHABLE`) and land when it is back.

**P6.** As P5 with the phone unable to reach the pod. Today: the relaunch hand-back is refused, the
watch drops to idle and the resends stop, the phone stays loaned. After the fix: the resends continue
until the phone accepts.

**P7.** In a loan, the watch off (`sim.sh watch off`) for 65 minutes with the phone reading the sensor.
Pass: phone `watch SILENT — no report for <m> min`, then `warning <k> of 3 issued` with the notice
`Watch Not Reporting` at about 20, 40 and 60 min; no take-back. A second run with the phone's sensor
reading stopped: no warning.

**P8.** In a loan, Take Back on the phone (the `Pod on Watch` tile, then `Reclaim Now`). Pass: phone
`reclaim ladder LIVE`; watch `REVOKED`; audit `R37 audit CLEAN`. With the watch not answering
(`sim.sh link` cut): `reclaim revoke RESENT (attempt 2 of 2)` at +10 s, `force reclaim SALVAGE` at
+25 s.

**P9.** In a loan, the watch off for over 330 s, then Take Back. Pass: phone `reclaim ladder DEAD —
… force NOW`, `force reclaim SALVAGE`, the `Watch Session Ended Without Hand-Back` notice.

**P10.** In a loan, `pod away`, then Take Back. Pass: at 5 min phone `R37: audit NEVER RAN … Session
UNVERIFIED, loop OPENS` and the notice `Watch Session Unverified`.

**P11.** Phone away, Start, `Start Anyway`. Pass: watch `REQUEST wait shortened`, `[seize] REQUEST TIMED
OUT — offering offline start`, `SEIZE confirmed`, `seized loan ACTIVE`. Phone back: watch `phone is back
— REUNION PROMPT`, alert `iPhone Is Back`; phone `[seize] RETRO-ACK — offer for a SEIZED loan`.

**P12.** Phone away, Start. Pass: watch `REQUEST sent … (phone unreachable — short 8s timeout)` and the
offline offer about 8 s later.

**P13.** No loan; a bolus and then a carb entry on the phone. Pass: phone and watch `[seize] dormant grant
refreshed` after each, at most once per 30 s. In a loan: watch `RX statusQuery ch=urgent`.

**P14.** In a loan, a 2 U watch bolus (`MANUAL BOLUS delivering`), then End while it is given. Pass:
watch `End REFUSED — the watch's bolus is still being delivered`, alert `Couldn't End Sport Mode`; End
after the bolus hands back. A carb entry on the watch reaches the phone. Take Back during a watch bolus
goes through (this line does not refuse it).

**P15.** Scripted glucose falling with no carbs, in a loan. Pass: watch `[lowbg] WARNED · <title>`
(`Likely low in <n> mins` and similar); with recent carbs, `no warning — carbs too recent`. Missed Meal
Notifications: a rise with no carbs, the toggle off then on; the phone logs only to the system log.
