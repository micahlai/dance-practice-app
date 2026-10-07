#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source_root="$project_root/dance-app/dance-app/dance-app"
fixture_root="$(mktemp -d /private/tmp/choreo-recording.XXXXXX)"

ffmpeg -hide_banner -loglevel error -f lavfi \
  -i 'color=c=red:s=640x360:r=30:d=4' -c:v libx264 -pix_fmt yuv420p \
  "$fixture_root/choreo-camera.mov"
ffmpeg -hide_banner -loglevel error -f lavfi \
  -i 'color=c=blue:s=640x360:r=30:d=8' -f lavfi \
  -i 'sine=frequency=440:duration=8' -c:v libx264 -pix_fmt yuv420p \
  -c:a aac -shortest "$fixture_root/choreo-reference.mp4"

xcrun swiftc -parse-as-library -swift-version 5 \
  -module-cache-path "$fixture_root/module-cache" \
  "$source_root/Features/Beats/BeatGrid.swift" \
  "$source_root/Features/SpeedControl/CountOffSequence.swift" \
  "$source_root/Core/Media/VideoDocument.swift" \
  "$source_root/Core/Media/DocumentStore.swift" \
  "$source_root/Features/Markers/Marker.swift" \
  "$source_root/Features/Recording/TakeDraft.swift" \
  "$source_root/Features/Recording/RecordingTimingSelection.swift" \
  "$source_root/Features/Recording/TakeExporter.swift" \
  "$project_root/tests/RecordingChecks.swift" \
  -o "$fixture_root/recording-checks"

"$fixture_root/recording-checks" "$fixture_root"
python3 "$project_root/tests/check_recording_exports.py" "$fixture_root"
printf 'Generated test videos: %s\n' "$fixture_root"
