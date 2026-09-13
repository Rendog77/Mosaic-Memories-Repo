#!/usr/bin/env bash
set -euo pipefail

device_kind="${1:-iPhone}"

device_id="$({
  xcrun simctl list devices available
} | awk -v kind="$device_kind" '$0 ~ kind && /Shutdown/ { identifier = $(NF - 1); gsub(/[()]/, "", identifier); print identifier; exit }')"

if [[ -z "$device_id" ]]; then
  echo "No available shutdown $device_kind simulator was found."
  exit 1
fi

app_path=".build/app-derived/Build/Products/Debug-iphonesimulator/MosaicMemories.app"
bundle_id="com.mosaicmemories.app"
expected_title="CI Relaunch Project"

echo "Running launch smoke test on $device_kind simulator $device_id"
xcrun simctl boot "$device_id"
xcrun simctl bootstatus "$device_id" -b
xcrun simctl install "$device_id" "$app_path"

data_container="$(xcrun simctl get_app_container "$device_id" "$bundle_id" data)"
projects_directory="$data_container/Library/Application Support/MosaicMemories/Projects"
probe_file="$data_container/tmp/mosaic-persistence-probe.txt"
mkdir -p "$projects_directory"
cp ci/fixtures/relaunch-project.json "$projects_directory/11111111-1111-1111-1111-111111111111.json"

export SIMCTL_CHILD_MOSAIC_CI_EXPECT_PROJECT_TITLE="$expected_title"
first_launch="$(xcrun simctl launch "$device_id" "$bundle_id")"
echo "$first_launch"
for _ in {1..20}; do
  [[ -f "$probe_file" ]] && break
  sleep 0.25
done
[[ "$(cat "$probe_file")" == "$expected_title" ]]
xcrun simctl terminate "$device_id" "$bundle_id"

rm "$probe_file"
second_launch="$(xcrun simctl launch "$device_id" "$bundle_id")"
echo "$second_launch"
for _ in {1..20}; do
  [[ -f "$probe_file" ]] && break
  sleep 0.25
done
[[ "$(cat "$probe_file")" == "$expected_title" ]]
xcrun simctl terminate "$device_id" "$bundle_id"
xcrun simctl shutdown "$device_id"

if [[ "$first_launch" != *"$bundle_id"* || "$second_launch" != *"$bundle_id"* ]]; then
  echo "The application did not report a successful launch."
  exit 1
fi
