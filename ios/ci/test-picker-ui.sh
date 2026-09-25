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

app_path=".build/app-derived/Build/Products/Debug-iphonesimulator/MosaicMemories.app"
bundle_id="com.mosaicmemories.app"
xcrun simctl install "$device_id" "$app_path"

data_container="$(xcrun simctl get_app_container "$device_id" "$bundle_id" data)"
projects_directory="$data_container/Library/Application Support/MosaicMemories/Projects"
assets_directory="$data_container/Library/Application Support/MosaicMemories/SelectedPhotos"
mkdir -p "$projects_directory" "$assets_directory"

hero_id="00000000-0000-0000-0000-000000000001"
cp "$fixture_path" "$assets_directory/$hero_id.asset"
sources_json=""
for index in $(seq 1 100); do
  source_id="$(printf '10000000-0000-0000-0000-%012d' "$index")"
  cp "$fixture_path" "$assets_directory/$source_id.asset"
  separator=""
  if [[ -n "$sources_json" ]]; then
    separator=","
  fi
  sources_json="${sources_json}${separator}{\"id\":\"${source_id}\",\"origin\":\"photoPicker\"}"
done

project_path="$projects_directory/33333333-3333-3333-3333-333333333333.json"
printf '%s' "{\"createdAt\":0,\"hero\":{\"id\":\"$hero_id\",\"origin\":\"photoPicker\"},\"heroCrop\":null,\"id\":\"33333333-3333-3333-3333-333333333333\",\"recipe\":{\"columns\":50,\"engineVersion\":1,\"likeness\":0.5,\"repeatWindow\":8,\"replacements\":[]},\"schemaVersion\":3,\"sources\":[${sources_json}],\"sourcesConfirmed\":false,\"title\":\"CI Source Review\",\"updatedAt\":0}" > "$project_path"

editor_source_one="10000000-0000-0000-0000-000000000001"
editor_source_two="10000000-0000-0000-0000-000000000002"
editor_project_path="$projects_directory/44444444-4444-4444-4444-444444444444.json"
printf '%s' "{\"createdAt\":1,\"hero\":{\"id\":\"$hero_id\",\"origin\":\"photoPicker\"},\"heroCrop\":null,\"id\":\"44444444-4444-4444-4444-444444444444\",\"recipe\":{\"columns\":2,\"engineVersion\":1,\"likeness\":0.5,\"repeatWindow\":1,\"replacements\":[]},\"schemaVersion\":3,\"sources\":[{\"id\":\"$editor_source_one\",\"origin\":\"photoPicker\"},{\"id\":\"$editor_source_two\",\"origin\":\"photoPicker\"}],\"sourcesConfirmed\":true,\"title\":\"CI Editor\",\"updatedAt\":1}" > "$editor_project_path"

xcodebuild \
  -project MosaicMemories.xcodeproj \
  -scheme MosaicMemories \
  -destination "platform=iOS Simulator,id=$device_id" \
  -derivedDataPath .build/app-derived \
  -resultBundlePath .build/picker-ui.xcresult \
  -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO \
  test
