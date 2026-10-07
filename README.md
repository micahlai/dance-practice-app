# Choreo Jogger

An iPad app for learning choreography from video and recording your own takes.
Import a reference, set its beat grid, slow it down, scrub through movement,
and loop the sections you want to practice. Record a take alongside the
reference, save it as a draft, and export it through Apple's share sheet.

Built with SwiftUI, UIKit, and AVFoundation. Video, beat analysis, practice
settings, and drafts stay on the device; no account or backend is required.

## Requirements

- macOS with Xcode 26 or newer; development builds have been verified with
  Xcode 26.6. The project uses Swift concurrency features supplied by that
  toolchain, with Swift 5 language mode.
- An iPad running iPadOS 17 or newer. Portrait and landscape are supported.
- A physical iPad to record camera footage and check Bluetooth/audio timing.
  The simulator can build and run the app but does not provide an iPad camera.
- Optional: `ffmpeg` and Python 3 for the standalone recording/export checks.

## Build and run

Open the project in Xcode:

```text
dance-app/dance-app/dance-app.xcodeproj
```

Select the **dance-app** scheme and an iPad simulator or connected iPad, then
run. For a physical device, choose your signing team in the target's
**Signing & Capabilities** settings.

From the repository root, build for the simulator:

```bash
xcodebuild \
  -project dance-app/dance-app/dance-app.xcodeproj \
  -scheme dance-app \
  -destination 'generic/platform=iOS Simulator' \
  build
```

The generic destination works even when a particular simulator's runtime
does not match the installed SDK. Launching the app still requires an
installed simulator runtime or a physical device. There are no backend
services or API keys to configure.

## Practice

1. Import a video using **Photos** or **Files**, or reopen a recent video.
2. Let the app analyze the audio for tempo. Adjust the BPM if needed, then
   use **Set 1** to anchor the first count. Counts cycle from 1 through 8;
   half counts appear as **&**.
3. Drag the jog wheel to scrub; pinch it to change the timeline scale.
   Scrub audio can be enabled independently of normal music playback.
4. Adjust speed along the right edge of the video, from 25% to 100%.
   Playback preserves audio pitch. Use the reset control to return to 100%.
5. Add markers to revisit sections and set A/B points for repeated practice.

The video supports pinch-to-zoom, panning, and double-tap reset. The Help
button opens a tour of the controls. The transport also offers count-off,
music during count-off, beat clicks, waveform display, optional frame
blending, and audio latency calibration. Beat clicks cycle through **Off**,
**every beat**, and **beat plus half count**.

The app restores the most recent practice session, including its saved beat
grid, speed, markers, and loop settings.

## Record a take

Press the recording button next to **Help** to open the **Record / Drafts**
workspace. The current practice video becomes the reference. Set these
options before recording:

| Setting | Behavior |
| --- | --- |
| Music starts at | Reference-video time at which music and reference playback begin. |
| Count-in lands at | Reference-video beat you want the countdown to lead into; snapped to the beat grid. |
| Recording speed | Reference playback speed, from 25% to 100%. |
| Adjust final video to 100% | Speeds up the camera take so the music returns to its original speed. |
| Reference layout | Camera only, side by side, or picture in picture; included in the final video. |
| Metronome | Off, counts 1–8, or counts with **&** half counts; audible while recording. |

Music start and count-in landing are independent: music can play before the
countdown begins. If the countdown needs to start before the selected music,
the recorder adds a lead-in. Count-in and metronome require a beat grid; set
it in practice first.

Tap **Choose** beside either time to open the timing popup. Preview the
reference at your recording speed, jog the existing wheel, and pinch to zoom
its waveform and beat grid. Saved markers and A/B bounds are visual guides
only: this popup does not edit them, loop playback, or move the practice
playhead. Use the beat/0.1-second buttons for precise adjustments, then
**Done** to apply or **Cancel** to leave the setting unchanged. Count-in
landings snap to a beat at/after music start and before the video ends.

For example, a 20-second camera take recorded at 50% becomes 10 seconds when
**Adjust final video to 100%** is enabled. With the option off, it stays
20 seconds and keeps the slower, pitch-preserved music.

Switch between front and back cameras, press **Record take**, and stop when
finished. Recording also stops at the end of the reference. Review the
composed video, then choose **Save as draft** or **Discard**. Settings are
locked during capture and review.

Exported audio comes from the reference video. The microphone is not
recorded, and the live metronome is excluded from the final soundtrack.
A reference without audio produces a silent take.

## Drafts, sharing, and storage

The **Drafts** tab lists saved takes. The home page also shows every take,
with its camera thumbnail, a preview and title of the original reference,
storage used by that draft, and total draft storage.

Open a draft to prepare its composed preview, then choose **Export / Share**.
The app renders an MP4 and opens Apple's share sheet, where available
destinations include Photos, Files, AirDrop, and other installed apps.
Camera access is requested for recording; saving to Photos may request
photo-library permission.

Each draft stores its own camera footage, reference-video copy, and settings.
Switching practice videos does not alter saved drafts. Storage figures
include those saved files; the total covers drafts, not the entire app's
practice-video library or temporary export files. Keeping a reference copy
for every draft increases storage usage.

Deleting a draft requires confirmation and removes that draft's saved files.
Its original practice video remains in the library. A take is persistent
only after **Save as draft**; an unsaved recording should not be relied on
to survive app termination.

## Verification

Run the standalone recording checks from the repository root:

```bash
bash tests/run_recording_checks.sh
```

The script compiles the production timing and exporter sources, generates
temporary red-camera/blue-reference fixtures with a 440 Hz soundtrack, and
checks:

- Count-in landing and music timing at four speeds and all eight counts.
- Camera-only, side-by-side, and picture-in-picture exports with speed
  correction enabled and disabled.
- Export duration, one clean audio track, and a take stopped before music starts.
- Rendered reference placement, visibility before music starts, and audio pitch.
- Draft save/reload, capture settings and source copies, storage accounting,
  failed-save rollback, and deletion that preserves the source videos.
- Cancellation before and during export.

The checks use temporary files and do not open the app's video library.
Generated videos are left in the temporary directory printed by the script
for inspection. On recent macOS versions, the harness may report
AVFoundation deprecation warnings for APIs retained to support iPadOS 17.

The simulator build and automated timing/export checks pass. Physical-device
and manual validation are still needed for camera/audio synchronization,
Bluetooth routes, portrait/landscape interactions, Dynamic Type, recording
interruptions, low storage, and individual share-sheet destinations.

## Project layout

```text
dance-app/dance-app/
  dance-app.xcodeproj/
  dance-app/
    App/                     App state and feature coordination
    Core/
      AudioAnalysis/         Waveform and tempo analysis
      Media/                 Imports and practice-session persistence
      Sync/                  Audio-route latency storage
    Features/
      Beats/                 Beat grid and BPM controls
      Calibration/           Audio latency calibration
      Import/                Home page and video import
      Markers/               Markers and A/B loops
      Onboarding/            Help tour
      Player/                Playback, zoom, and frame blending
      Recording/             Capture, take drafts, rendering, and sharing
      Shell/                 Adaptive practice layout
      SpeedControl/          Speed gestures and shared count-off audio
      Timeline/              Jog wheel and scrub audio
docs/                        Project conventions, milestones, and status
tests/                       Standalone recording/export verification
```

Imported media and practice sidecars are stored in the app's Application
Support **Videos** directory. Drafts live under **Takes**, in one directory
per take. Reference playback owns the media playhead; recording guides and
exports derive timing from capture-time settings rather than current
practice controls.

See [project state](docs/PROJECT_STATE.md) for implementation status and
remaining device checks, [milestones](docs/MILESTONES.md) for acceptance
criteria, and [project conventions](docs/CLAUDE.md) for architecture details.

## Current boundaries

The current import screen supports local Photos and Files. It does not
download videos from TikTok or YouTube. A share-in extension, iPhone layout,
cloud sync, stem separation, and crowd-noise removal remain deferred.
