#!/usr/bin/env bash
set -euo pipefail

device_id="$(xcrun simctl list devices available | awk '$0 ~ /iPhone/ && /Shutdown/ { identifier = $(NF - 1); gsub(/[()]/, "", identifier); print identifier; exit }')"
if [[ -z "$device_id" ]]; then
  echo "No available shutdown iPhone simulator was found."
  exit 1
fi

xcodebuild \
  -project MosaicMemories.xcodeproj \
  -scheme MosaicMemories \
  -destination "platform=iOS Simulator,id=$device_id" \
  -derivedDataPath .build/app-derived \
  -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO \
  test
