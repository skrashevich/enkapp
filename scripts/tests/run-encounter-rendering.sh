#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
SIMULATOR="${1:-$(xcrun simctl list devices available --json | python3 -c 'import json,sys; print(next(d["udid"] for devices in json.load(sys.stdin)["devices"].values() for d in devices if "iPhone" in d["name"]))')}"
TEST_ROOT="${TMPDIR:-/tmp}/enkapp-rendering-regression"
APP="$TEST_ROOT/EncounterRenderingTests.app"
mkdir -p "$APP" "$TEST_ROOT/module-cache"
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
xcrun --sdk iphonesimulator swiftc -sdk "$SDK" -target arm64-apple-ios18.0-simulator -module-cache-path "$TEST_ROOT/module-cache" \
  scripts/tests/EncounterRenderingTests.swift encx-cli/EncounterHTMLView.swift SharedCore/EncounterHTMLContent.swift \
  SharedCore/EncounterModels.swift encx-cli/CoordinateText.swift SharedCore/GameTheme.swift encx-cli/ZoomableImageViewer.swift \
  -o "$APP/EncounterRenderingTests"
cat > "$APP/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>dev.enkapp.rendering-regression</string>
<key>CFBundleExecutable</key><string>EncounterRenderingTests</string>
<key>CFBundleName</key><string>Rendering Tests</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>UILaunchScreen</key><dict/>
<key>MinimumOSVersion</key><string>18.0</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
xcrun simctl boot "$SIMULATOR" 2>/dev/null || true
xcrun simctl bootstatus "$SIMULATOR" -b
xcrun simctl terminate "$SIMULATOR" dev.enkapp.rendering-regression 2>/dev/null || true
xcrun simctl install "$SIMULATOR" "$APP"
DATA=$(xcrun simctl get_app_container "$SIMULATOR" dev.enkapp.rendering-regression data)
rm -f "$DATA/Documents/results.json"
xcrun simctl launch "$SIMULATOR" dev.enkapp.rendering-regression
for ((i=0; i<80; i++)); do
  if [[ -f "$DATA/Documents/results.json" ]]; then
    cp "$DATA/Documents/results.json" "$TEST_ROOT/results.json"
    cp "$DATA/Documents/"*.png "$TEST_ROOT/" 2>/dev/null || true
    cat "$TEST_ROOT/results.json"
    echo "Artifacts: $TEST_ROOT"
    python3 -c 'import json,sys;sys.exit(not json.load(open(sys.argv[1]))["passed"])' "$TEST_ROOT/results.json"
    exit $?
  fi
  sleep 1
done
echo "Rendering tests timed out" >&2
exit 1
