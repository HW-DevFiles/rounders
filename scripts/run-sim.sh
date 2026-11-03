#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
cd "$ROOT"
DERIVED_DATA=${ROUNDERS_DERIVED_DATA:-${TMPDIR:-/tmp}/rounders-derived-data}
SIM_ID=${SIMULATOR_UDID:-}
if [[ -z "$SIM_ID" ]]; then
    SIM_ID=$(xcrun simctl list devices available -j | python3 -c 'import json,sys; d=json.load(sys.stdin); print(next((x["udid"] for devices in d["devices"].values() for x in devices if x["name"]=="rounders-demo"),""))')
fi
if [[ -z "$SIM_ID" ]]; then
    RUNTIME=$(xcrun simctl list runtimes -j | python3 -c 'import json,sys; r=[x for x in json.load(sys.stdin)["runtimes"] if x["isAvailable"] and x["identifier"].startswith("com.apple.CoreSimulator.SimRuntime.iOS-")]; r.sort(key=lambda x:tuple(map(int,x["version"].split(".")))); print(r[-1]["identifier"] if r else "")')
    if [[ -z "$RUNTIME" ]]; then echo 'Install an iOS simulator runtime in Xcode Settings → Components.' >&2; exit 1; fi
    SIM_ID=$(xcrun simctl create rounders-demo com.apple.CoreSimulator.SimDeviceType.iPhone-17 "$RUNTIME")
fi
xcodebuild -project Rounders.xcodeproj -scheme Rounders -destination "platform=iOS Simulator,id=$SIM_ID" -derivedDataPath "$DERIVED_DATA" build
STATE=$(xcrun simctl list devices -j | python3 -c 'import json,sys; target=sys.argv[1]; print(next(x["state"] for ds in json.load(sys.stdin)["devices"].values() for x in ds if x["udid"]==target))' "$SIM_ID")
if [[ "$STATE" != Booted ]]; then xcrun simctl boot "$SIM_ID"; fi
xcrun simctl bootstatus "$SIM_ID" -b
XCODE_DIR=$(xcode-select -p)
if [[ -d "$XCODE_DIR/Applications/Simulator.app" ]]; then
    open -a "$XCODE_DIR/Applications/Simulator.app" --args -CurrentDeviceUDID "$SIM_ID"
elif [[ -d "$XCODE_DIR/../Applications/DeviceHub.app" ]]; then
    open -a "$XCODE_DIR/../Applications/DeviceHub.app" --args -CurrentDeviceUDID "$SIM_ID"
fi
xcrun simctl install "$SIM_ID" "$DERIVED_DATA/Build/Products/Debug-iphonesimulator/Rounders.app"
# Relaunching the demo is intentional; no other simulator app is touched.
xcrun simctl terminate "$SIM_ID" dev.rounders.game >/dev/null 2>&1 || true
xcrun simctl launch "$SIM_ID" dev.rounders.game "$@"
echo "Rounders launched on $SIM_ID. Select rounders-demo in the simulator window."
