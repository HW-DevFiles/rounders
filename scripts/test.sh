#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
SCRATCH=${ROUNDERS_TEST_BUILD:-${TMPDIR:-/tmp}/rounders-tests}
swift test --package-path "$ROOT/Packages/RoundersSim" --scratch-path "$SCRATCH" -c release
BIN=$(swift build --package-path "$ROOT/Packages/RoundersSim" --scratch-path "$SCRATCH" -c release --show-bin-path)
PROOF=$(mktemp -d "${TMPDIR:-/tmp}/rounders-replay.XXXXXX")
trap 'rm -rf "$PROOF"' EXIT
"$BIN/ReplayCheck" > "$PROOF/first"
"$BIN/ReplayCheck" > "$PROOF/second"
cmp "$PROOF/first" "$PROOF/second"
cmp "$ROOT/scripts/replay-42.txt" "$PROOF/first"
echo 'Replay hash matches in two independent processes.'
