#!/usr/bin/env bash
set -euo pipefail

device_id="$({
  xcrun simctl list devices available
} | awk '/iPhone/ && /Shutdown/ { identifier = $(NF - 1); gsub(/[()]/, "", identifier); print identifier; exit }')"

if [[ -z "$device_id" ]]; then
  echo "No available shutdown iPhone simulator was found."
  exit 1
fi

app_path=".build/app-derived/Build/Products/Debug-iphonesimulator/MosaicMemories.app"
bundle_id="com.mosaicmemories.app"

xcrun simctl boot "$device_id"
xcrun simctl bootstatus "$device_id" -b
xcrun simctl install "$device_id" "$app_path"

first_launch="$(xcrun simctl launch "$device_id" "$bundle_id")"
echo "$first_launch"
xcrun simctl terminate "$device_id" "$bundle_id"

second_launch="$(xcrun simctl launch "$device_id" "$bundle_id")"
echo "$second_launch"
xcrun simctl terminate "$device_id" "$bundle_id"
xcrun simctl shutdown "$device_id"

if [[ "$first_launch" != *"$bundle_id"* || "$second_launch" != *"$bundle_id"* ]]; then
  echo "The application did not report a successful launch."
  exit 1
fi
