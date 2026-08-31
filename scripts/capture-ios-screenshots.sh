#!/usr/bin/env bash
set -euo pipefail

PROJECT=${PROJECT:-encx-cli.xcodeproj}
SCHEME=${SCHEME:-encx-cli}
CONFIGURATION=${CONFIGURATION:-Debug}
IPHONE_SIMULATOR_NAME=${IPHONE_SIMULATOR_NAME:-${SIMULATOR_NAME:-}}
IPAD_SIMULATOR_NAME=${IPAD_SIMULATOR_NAME:-}
BUILD_DIR=${BUILD_DIR:-build}
DERIVED_DATA=${DERIVED_DATA:-$BUILD_DIR/ScreenshotDerivedData}
OUTPUT_DIR=${OUTPUT_DIR:-$BUILD_DIR/screenshots}
BUNDLE_ID=${BUNDLE_ID:-com.svk-team.encx-cli}
IPHONE_SIZE=${IPHONE_SIZE:-1284x2778}
IPAD_SIZE=${IPAD_SIZE:-2064x2752}

rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR" "$DERIVED_DATA"

iphone_device_type=$(xcrun simctl list devicetypes --json | \
  /usr/bin/python3 -c 'import json,sys
requested=sys.argv[1]
preferred=[
    "iPhone 13 Pro Max",
    "iPhone 12 Pro Max",
    "iPhone 11 Pro Max",
    "iPhone 17 Pro Max",
    "iPhone 17 Pro",
    "iPhone 16 Pro Max",
    "iPhone 16 Pro",
    "iPhone 15 Pro Max",
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
raise SystemExit("No available iPhone simulator device type found")' "$IPHONE_SIMULATOR_NAME")

ipad_device_type=$(xcrun simctl list devicetypes --json | \
  /usr/bin/python3 -c 'import json,sys
requested=sys.argv[1]
preferred=[
    "iPad Pro 13-inch (M5)",
    "iPad Pro 13-inch (M4)",
    "iPad Pro 12.9-inch (6th generation)",
    "iPad Pro 12.9-inch (5th generation)",
    "iPad Pro 12.9-inch (4th generation)",
]
data=json.load(sys.stdin)
types=[item for item in data.get("devicetypes", []) if item.get("name", "").startswith("iPad")]
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
raise SystemExit("No available iPad simulator device type found")' "$IPAD_SIMULATOR_NAME")

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

iphone_udid=$(xcrun simctl create "enkapp iPhone Screenshots $$" "$iphone_device_type" "$runtime")
ipad_udid=$(xcrun simctl create "enkapp iPad Screenshots $$" "$ipad_device_type" "$runtime")
cleanup() {
  xcrun simctl shutdown "$iphone_udid" >/dev/null 2>&1 || true
  xcrun simctl shutdown "$ipad_udid" >/dev/null 2>&1 || true
  xcrun simctl delete "$iphone_udid" >/dev/null 2>&1 || true
  xcrun simctl delete "$ipad_udid" >/dev/null 2>&1 || true
}
trap cleanup EXIT

destination="platform=iOS Simulator,id=$iphone_udid"

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

resize_png() {
  local path=$1
  local size=$2
  local width=${size%x*}
  local height=${size#*x}
  sips -z "$height" "$width" "$path" >/dev/null
}

capture_device() {
  local udid=$1
  local output_dir=$2
  local size=$3
  mkdir -p "$output_dir"

  xcrun simctl boot "$udid" >/dev/null 2>&1 || true
  xcrun simctl bootstatus "$udid" -b
  xcrun simctl install "$udid" "$app_path"
  xcrun simctl privacy "$udid" revoke notifications "$BUNDLE_ID" >/dev/null 2>&1 || true
  xcrun simctl ui "$udid" appearance dark

  xcrun simctl launch --terminate-running-process "$udid" "$BUNDLE_ID" --screenshots
  sleep 3
  xcrun simctl io "$udid" screenshot "$output_dir/01-games.png"
  resize_png "$output_dir/01-games.png" "$size"

  xcrun simctl launch --terminate-running-process "$udid" "$BUNDLE_ID" --screenshots --screenshot-game
  sleep 2
  xcrun simctl io "$udid" screenshot "$output_dir/02-game.png"
  resize_png "$output_dir/02-game.png" "$size"

  xcrun simctl launch --terminate-running-process "$udid" "$BUNDLE_ID" --screenshots --screenshot-settings
  sleep 2
  xcrun simctl io "$udid" screenshot "$output_dir/03-settings.png"
  resize_png "$output_dir/03-settings.png" "$size"

  xcrun simctl launch --terminate-running-process "$udid" "$BUNDLE_ID" --screenshots --screenshot-team
  sleep 2
  xcrun simctl io "$udid" screenshot "$output_dir/04-team.png"
  resize_png "$output_dir/04-team.png" "$size"

  xcrun simctl launch --terminate-running-process "$udid" "$BUNDLE_ID" --screenshots --screenshot-tools
  sleep 2
  xcrun simctl io "$udid" screenshot "$output_dir/05-tools.png"
  resize_png "$output_dir/05-tools.png" "$size"

  xcrun simctl launch --terminate-running-process "$udid" "$BUNDLE_ID" --screenshots --screenshot-anagramizer
  sleep 2
  xcrun simctl io "$udid" screenshot "$output_dir/06-anagramizer.png"
  resize_png "$output_dir/06-anagramizer.png" "$size"

  xcrun simctl launch --terminate-running-process "$udid" "$BUNDLE_ID" --screenshots --screenshot-onboarding
  sleep 2
  xcrun simctl io "$udid" screenshot "$output_dir/07-onboarding.png"
  resize_png "$output_dir/07-onboarding.png" "$size"
}

capture_device "$iphone_udid" "$OUTPUT_DIR/iphone" "$IPHONE_SIZE"
capture_device "$ipad_udid" "$OUTPUT_DIR/ipad" "$IPAD_SIZE"

echo "==> $OUTPUT_DIR"
