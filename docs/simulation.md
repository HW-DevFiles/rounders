# Milestone 1 simulation contract

`RaceState` is a value snapshot. `step` runs exactly one 60 Hz tick using integers (Q16 positions, 65,536 units per tile). The app’s camera, rendering, sound and hardware mapping are outside this boundary. Bots generate movement inputs through the same movement function as the player; their plans, route choices and PCG streams are snapshot state. There are no speed cheats or player-future inputs.

## Ordering and timers

Places use finish tick, then forward position, then runner ID. Global Tax is evaluated first. Runners step in rotating `(tick + index) % 6` order: choose routes, decrement timers, decide/use a Hand, move, collect personal Parcels, contact traps. Projectiles advance after all runners. Finish and race-completion rules run last. Events have monotonically increasing `(tick, sequence)` identifiers and a capacity of 64; presentation consumes each once.

All durations are simulation ticks. Newly activated local buffs last their full specified number of ticks including the activation tick. A Bill applies for 360 ticks beginning at the following tick’s global phase. Traps can contact on placement and lose their first life tick at that tick’s end. A Hand use starts a 30-tick lockout and its own roll cooldown; the next use is permitted 30 ticks later. Cooldowns are `[480, 900, 480, 600, 540, 600, 480, 360]` for the Starter list in README order.

Hands are press events, with no repeat while held. Simultaneous Hand presses select Left; a failed Left attempt does not fall through to Right. Movement is held state plus a pending press: a short click survives zero-tick render frames and is consumed once, rather than repeated across catch-up ticks. Generic controller polling is supplemented by edge capture for between-poll presses.

The app accepts at most five ticks of wall-clock debt. Overload slows game time rather than jumping authoritative state ahead; interpolation is clamped to `[0,1]`. Pause, restart, backgrounding and screen changes reset the wall clock and pending gameplay input. Currently held controls must be released before they can act on a new screen. The scene continues polling on Title, Pause and Results while simulation stepping is suspended.

## Starter interactions

| Case | Rule |
|---|---|
| Dart geometry | Spawn at front edge, 1.2 tiles above feet; vertical hit half-size 0.1 tile. Advances 24,030 Q16 units/tick (22 tiles/s), maximum 18 tiles. Solids stop it. Standing bodies can be hit; Tuck can dodge it. |
| Dart eligibility | A live, unfinished rival ahead, within 18 tiles, at shot height and with no solid tile in the line. Nearest x wins; equal x uses lowest runner ID. No target keeps the Knack. |
| Dart contact | Swept horizontal segment against runner box. First x, then ID. Solid collision wins if a solid and runner occupy the same movement segment. Hit consumes the shot even if Guard or immunity stops the effect. |
| Bill | Latest Bill resets the six-second timer, sender, affected mask and blocked mask. Only the current leader is taxed; sender exempt. A Guard absorbs that Bill once for that runner, including future lead changes during the same Bill. A new Bill is a new attack. |
| Tax, immunity, Shake-off | Respawn invulnerability and Tamper Seal suppress Tax. A new Bill’s first status hit waits out Shake-off; once accepted, its continuous Tax does not repeatedly trigger Shake-off. Tamper Seal clears Tax on the use tick. Guard does not clear Tax already accepted. |
| Status hits | Guard absorbs before status immunity / Shake-off. A successful status hit starts 45 ticks of Shake-off; hits ignored during it do not refresh anything. A stronger or equal slow replaces the previous slow and duration; a weaker hit cannot shorten or extend the stronger slow. Gum’s Hop prohibition is independent when its hit succeeds. |
| Speed composition | Local speed buffs replace each other. Strongest slow wins, including Tax; slows do not multiply. Surface, Tuck drag and Plonk-roll modifiers then apply, with final target clamped to ×0.45…×1.70. Air momentum follows the reference acceleration/drag rules. |
| Guard and lethal contact | Guard absorbs one complete continuous terrain-hazard contact. A contact latch prevents death on the next overlapping tick; leaving and re-entering is a new contact. Pits and anti-stuck recovery bypass Guard. |
| Traps | Pins are centred 1.5, 3 and 4.5 tiles behind, 0.8 tiles wide. Gum spans 1…5 tiles behind. Each drops to the first floor within 12 tiles below its own location; absence wastes it. One pin disappears on contact. Gum records a per-runner trigger mask. Owners are immune. |
| Trap limits | Three placed groups per owner; adding another removes the oldest surviving group. Pins count as one group. Maximum 54 trap entries and 32 projectiles. |
| Parcel rolls | Per-runner PCG stream. Exclude cooldown entries and last used Knack. Rank/category weights are shared by humans and bots. No eligible entry spends the Parcel and leaves the Hand empty. Full Hands spend the Parcel without advancing the roll stream. |
| Bonk | 66 ticks out, then last Anchor at zero speed and 75 ticks of invulnerability. Clears status, speed buffs and movement buffers; retains Hands, roll cooldowns and Parcel bits. Previously placed traps/projectiles remain. Third Bonk at one Anchor selects a safe forward Anchor within 48 tiles. |
| Recovery / race end | Extra Anchor at x=530 follows the final gap; map rows are unchanged. Anti-stuck Bonk after 300 ticks without one tile of progress. A 10,800-tick limit guarantees Results even if a player never finishes; unfinished runners display DNF. |

## Replay fixture and hashing

`ReplayCheck` uses simulation version 1, bundled Laundry Lane, seed 42, hazard clock offset 2200, Regular difficulty with autoplay, cast IDs 0…5, and no external player frames. The six setups are bot tiers `[1,0,1,1,1,2]`; seeded shuffling assigns the starting grid. Run until `complete`. The expected result is checked in at `scripts/replay-42.txt` and executed twice in separate processes by `scripts/test.sh`.

`stateHash` uses FNV-1a with the published 64-bit offset basis and prime. Its explicit field order is in `StateHash.swift`. Integers are 64-bit little endian, booleans are integer 0/1, arrays are count-prefixed, strings are UTF-8 count-prefixed, optionals have a presence flag. Coverage includes configuration, all Runner movement/status state, Hands, acquisition ticks, cooldowns, Parcel masks, both kinds of RNG stream, complete bot plans/recipes/bands, route choices, Bill masks, projectiles, traps and event sequencing. No process-seeded hashing or unordered collection is involved.

The course is immutable input to stepping, separate from the race snapshot. A replay must use the same bundled course and tuning. The map rows’ SHA-256 is retained in the tests; the additional x=530 Anchor is covered separately. Golden fixtures were generated from this implementation’s normative interaction rules, rather than copied from the discarded prototype race harness.

## Validation boundary

Automated tests establish movement tables, the approved gap-2 sampling boundary, map data, all seven forced routes, the 40-seed tier ladder, every Starter, safety rules, replay/rollback, pad mapping, short taps, overload and transitions. Simulator tests exercise actual touch routing at different camera positions/orientations, menus and the GameController snapshot read path. A source-boundary inspection checks the simulation for prohibited imports, floating-point types and nondeterministic APIs; behavioral tests execute public interfaces rather than search implementation text.

Physical PS5 forwarding and human play feel remain manual checks. A virtual controller or passing snapshot test is not evidence that macOS forwarded a paired physical pad into DeviceHub.
