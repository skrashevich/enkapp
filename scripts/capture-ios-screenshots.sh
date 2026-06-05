#!/usr/bin/env bash
set -euo pipefail

PROJECT=${PROJECT:-encx-cli.xcodeproj}
SCHEME=${SCHEME:-encx-cli}
CONFIGURATION=${CONFIGURATION:-Debug}
SIMULATOR_NAME=${SIMULATOR_NAME:-}
BUILD_DIR=${BUILD_DIR:-build}
DERIVED_DATA=${DERIVED_DATA:-$BUILD_DIR/ScreenshotDerivedData}
OUTPUT_DIR=${OUTPUT_DIR:-$BUILD_DIR/screenshots}
BUNDLE_ID=${BUNDLE_ID:-com.svk-team.encx-cli}

mkdir -p "$OUTPUT_DIR" "$DERIVED_DATA"

device_type=$(xcrun simctl list devicetypes --json | \
  /usr/bin/python3 -c 'import json,sys
requested=sys.argv[1]
preferred=[
    "iPhone 17 Pro Max",
    "iPhone 16 Pro Max",
    "iPhone 15 Pro Max",
    "iPhone 17 Pro",
    "iPhone 16 Pro",
    "iPhone 15 Pro",
]
data=json.load(sys.stdin)
types=[item for item in data.get("devicetypes", []) if item.get("name", "").startswith("iPhone")]
if requested:
    preferred.insert(0, requested)
for name in preferred:
    for item in types:
        if item.get("name") == name:
            print(item["identifier"])
            raise SystemExit
if types:
    print(types[0]["identifier"])
    raise SystemExit
raise SystemExit("No available iPhone simulator device type found")' "$SIMULATOR_NAME")

runtime=$(xcrun simctl list runtimes --json | \
  /usr/bin/python3 -c 'import json,sys
data=json.load(sys.stdin)
runtimes=[
    item
    for item in data.get("runtimes", [])
    if item.get("isAvailable") and item.get("platform") == "iOS"
]
if not runtimes:
    raise SystemExit("No available iOS simulator runtime found")
runtimes.sort(key=lambda item: item.get("version", "0"))
print(runtimes[-1]["identifier"])')

udid=$(xcrun simctl create "enkapp Screenshots $$" "$device_type" "$runtime")
cleanup() {
  xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
  xcrun simctl delete "$udid" >/dev/null 2>&1 || true
}
trap cleanup EXIT

destination="platform=iOS Simulator,id=$udid"

xcodebuild build \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "$destination" \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY=- \
  DEVELOPMENT_TEAM=

app_path=$(find "$DERIVED_DATA/Build/Products" -path "*-iphonesimulator/*.app" -name "encx-cli.app" -print -quit)
if [[ -z "$app_path" ]]; then
  echo "Simulator app was not built" >&2
  exit 1
fi

xcrun simctl boot "$udid" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$udid" -b
xcrun simctl install "$udid" "$app_path"
xcrun simctl privacy "$udid" revoke notifications "$BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl ui "$udid" appearance dark

xcrun simctl launch --terminate-running-process "$udid" "$BUNDLE_ID" --screenshots
sleep 3
xcrun simctl io "$udid" screenshot "$OUTPUT_DIR/01-games.png"

xcrun simctl launch --terminate-running-process "$udid" "$BUNDLE_ID" --screenshots --screenshot-game
sleep 2
xcrun simctl io "$udid" screenshot "$OUTPUT_DIR/02-game.png"

xcrun simctl launch --terminate-running-process "$udid" "$BUNDLE_ID" --screenshots --screenshot-settings
sleep 2
xcrun simctl io "$udid" screenshot "$OUTPUT_DIR/03-settings.png"

echo "==> $OUTPUT_DIR"
