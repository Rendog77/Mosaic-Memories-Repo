#!/usr/bin/env bash
set -euo pipefail

device_id="$(xcrun simctl list devices available | awk '$0 ~ /iPhone/ && /Shutdown/ { identifier = $(NF - 1); gsub(/[()]/, "", identifier); print identifier; exit }')"
if [[ -z "$device_id" ]]; then
  echo "No available shutdown iPhone simulator was found."
  exit 1
fi

fixture_path=".build/picker-photo.png"
mkdir -p .build
/usr/bin/base64 -D < ci/fixtures/picker-photo.png.base64 > "$fixture_path"
xcrun simctl boot "$device_id"
xcrun simctl bootstatus "$device_id" -b
xcrun simctl addmedia "$device_id" "$fixture_path"

xcodebuild \
  -project MosaicMemories.xcodeproj \
  -scheme MosaicMemories \
  -destination "platform=iOS Simulator,id=$device_id" \
  -derivedDataPath .build/app-derived \
  -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO \
  test
