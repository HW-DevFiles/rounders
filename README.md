# Rounders

An original six-runner platform racer for iPhone, built with Swift 6 and SpriteKit. You are Clem, a clementine courier racing five named AI rivals across **Laundry Lane**. Running is automatic; timing your Hops, Tucks, Plonks and postal power-ups wins the round.

This milestone includes one complete course with three route forks, Errand and Regular difficulty, eight Starter Knacks, two held-item Hands, touch/mouse controls, GameController polling, keyboard fallback, pause/restart/results, code-drawn art and synthesised effects. No accounts, network play, progression, paid capabilities or external dependencies.

## Play on the Mac’s iPhone simulator

Install Xcode and an iOS simulator runtime, select Xcode’s command-line tools, then run:

```sh
./scripts/run-sim.sh
```

The script builds, creates/reuses a dedicated **rounders-demo** iPhone 17 simulator, boots it, installs the game and launches the Title screen. Select that device in the simulator window if several devices are open. Xcode 27.1 uses **DeviceHub**; older Xcode versions use **Simulator**. The deployment target is iOS 17.0; validation used Xcode 27.1 and the iOS 27.0 runtime.

Choose **LET’S ROUND**. Errand is the default; Difficulty switches to the tougher Regular field. Each round has a three-second countdown. A race ends when all runners finish, ten seconds after you finish, or at the three-minute limit. Unfinished runners are ordered by distance and shown as **DNF**.

For a deterministic spectator run or input diagnostics:

```sh
./scripts/run-sim.sh -autoplay -seed 42 -inputDebug
```

`-autoplay` makes Clem a Regular bot, reaches Results and logs `ROUNDERS_RESULT` with the seed, six runner results and a state hash. `-seed N` fixes the starting grid and random streams. `-inputDebug` shows live/seen input, actual touch-zone counters, controller count and simulation tick. The simulator’s permanent virtual controller may appear even with no physical pad attached; controller count is not proof of a connected PS5 controller.

Optional environment variables: `SIMULATOR_UDID` selects an existing device; `ROUNDERS_DERIVED_DATA` changes the build directory (otherwise it is under the system temporary directory).

## Controls

| Action | Touch / simulator mouse | PS5 controller | Keyboard fallback |
|---|---|---|---|
| Hop | Hold the right half, outside the Hand circle | Cross | Space, W or Up |
| Tuck on ground / Plonk in air | Hold the left half, outside the Hand circle | Circle, D-pad Down or left stick down | S or Down |
| Left Hand Knack | Click/tap the left yellow circle | L1 or L2 | Q |
| Right Hand Knack | Click/tap the right yellow circle | R1 or R2 | E |
| Pause / resume | Pause button, then Resume | Triangle; Options on supported hardware | P or Esc |
| Menu choice | Click the choice | D-pad / left stick Up or Down; Cross confirms, Circle goes back | Up/Down, Space or Enter confirms, Esc goes back |

Hold Hop longer for a higher jump (up to about 3 tiles). Hold Down when a Plonk lands after falling at least 1.5 tiles to get a **Plonk-roll** boost. Low arches require Tuck. The mouse acts as one finger, so it cannot hold two controls simultaneously; quick changes near screen centre work with the early-hop buffer. A touch keeps its original action until lifted, even if it moves over another zone. Controls stay fixed on screen as the camera scrolls, in either landscape orientation.

Collect yellow Parcels to fill your Left Hand, then Right Hand. Each parcel is personal to each runner and can be collected once. Full Hands waste a parcel. A dim Hand is empty, locked out, or has no valid target. Using a Knack starts a half-second shared lockout; holding a Hand button does not repeatedly fire it. Left Hand wins simultaneous Hand presses.

| Starter Knack | Effect |
|---|---|
| Paper Dart | Straight shot, 22 tiles/s over 18 tiles; 0.9 s Stagger. Tuck or hop to dodge. Needs a rival ahead in line. |
| Overdue Bill | Taxes the current leader at ×0.90 for 6 s; sender exempt. Follows lead changes. |
| Drawing Pins | Three floor pins behind you, lasting 12 s; each applies 0.6 s Stagger once. |
| Gum Patch | Four tiles behind you, lasting 10 s; slows a rival for 0.6 s and prevents Hop for 0.5 s. |
| Bubble Mailer | Three-second Guard, absorbing one attack, trap or hazard contact. Cannot save a fall into a pit. |
| Tamper Seal | Clears status immediately and prevents status for 2 s. Usable while Stunned. |
| Tailwind | ×1.25 speed for 2.5 s. |
| First Class | Instant speed-up to ×1.40 for 1.2 s. Replaces an existing speed buff. |

A Bonk costs 1.1 s out of play and returns you to your last Anchor, with 1.25 s invulnerability. You keep your Hands and collected-parcel record. Three Bonks at the same Anchor advance you to the next safe Anchor. Laundry Lane includes an additional safe Anchor after the final gap.

## Connect a PS5 controller

1. If already paired, press the controller’s **PS** button. Otherwise hold **Create + PS** until the light flashes, then select the DualSense in macOS **System Settings → Bluetooth**. USB is also usable.
2. Keep the simulator window in front. Launch with `-inputDebug` and press Cross: `input:hop` / `padSeen` should change. Check Circle, L1/R1, L2/R2, Triangle, D-pad and left stick too.
3. Use **Triangle to pause**. Xcode’s simulator bridge does not forward Options on the tested runtime; Options remains mapped for real hardware.
4. Touch/mouse and controller input are combined, so clicks continue to work while the pad is connected. Prompts follow the last input used.

The game polls every generic extended gamepad; it never requires a DualSense-specific profile. Snapshot-controller tests exercise the real GameController read path and a disconnect seam. **Physical DualSense forwarding, reconnect and a complete hand-played race still need a person’s check on this Mac.** They cannot be established by a virtual-controller test. If the simulator keeps its fake controller when a pad is switched off, the game cannot detect that physical disconnect; use the on-screen pause button. On hardware where the last-used controller disappears, the race pauses.

Keyboard bindings are available when the simulator forwards hardware keyboard input. They are a convenience; mouse and controller are the primary demo inputs.

## Build and validate

Open `Rounders.xcodeproj`, select the **Rounders** scheme and an iPhone simulator, then Run. No XcodeGen or third-party packages are needed.

```sh
# Simulation, physics, routes, 40 seeds per bot tier, Knacks, input,
# deterministic replay/rollback and separate-process golden hash:
./scripts/test.sh

# Equivalent package unit tests:
(cd Packages/RoundersSim && swift test -c release)

# Simulator UI tests (set SIM_ID to an available/booted iPhone simulator UDID):
xcodebuild -project Rounders.xcodeproj -scheme Rounders \
  -destination "platform=iOS Simulator,id=$SIM_ID" \
  -derivedDataPath /tmp/rounders-ui -only-testing:RoundersUITests test

# Device-architecture compile; no signing identity required:
xcodebuild -project Rounders.xcodeproj -scheme Rounders -sdk iphoneos \
  -destination 'generic/platform=iOS' -derivedDataPath /tmp/rounders-device \
  CODE_SIGNING_ALLOWED=NO build
```

Simulator UI tests press all four zones before and after scrolling and landscape reversal, exercise pause/restart/title, and verify a snapshot controller’s face buttons, shoulders, triggers, D-pad, stick and disconnect path. The scene uses 210 nodes, below its 300-node budget. The simulation tests cover all seven Laundry Lane routes without Bonks and with full route adherence. The gap-2 timing fixture accepts 40 ticks (667 ms): firstmate approved this one-tick sampling boundary difference from the design’s 39; shifting the approach by a quarter tick measures 39. All other gap/wall windows and hop/plonk tables match.

GitHub Actions runs the package/replay checks plus simulator and unsigned device builds.

The map rows retain SHA-256 `5d00e468b8fdbb4bfb3aeebd69025277c8d4203c691767331e24871569f511ab`; it has 18 parcels, 4 timed hazards and **23 anchors** after the approved recovery fix. [Simulation rules](docs/simulation.md) specify edge cases and the replay format.

### Free personal-team signing later

Simulator builds need no Apple account. For a future physical-device install, create the git-ignored `Config/Signing.local.xcconfig`:

```xcconfig
DEVELOPMENT_TEAM = YOUR_TEAM_ID
PRODUCT_BUNDLE_IDENTIFIER = your.unique.rounders.id
```

Select your free personal team in Xcode. The project uses automatic signing, a blank team by default, and no entitlements or paid capabilities. Real-device installation, TestFlight and App Store distribution are outside this milestone.

## Project layout

- `Rounders/`: SwiftUI screens, SpriteKit presentation, hardware input and audio.
- `Packages/RoundersSim/Sources/RoundersSim`: integer-only value simulation, movement, bots, combat, events and canonical hash. No Apple game/UI frameworks or Foundation.
- `RoundersContent`: validated JSON loading and the bundled course.
- `RoundersInput`: pure pad mapping, tick clock and input latches, outside the integer simulation boundary.
- `RoundersUITests/`: simulator integration tests.
- `scripts/`: simulator launch and repeatable validation.

MIT licensed. All visuals and sounds are generated by code. Other courses, additional Knacks, unlocks, arena elimination, online play and production assets are deferred.
