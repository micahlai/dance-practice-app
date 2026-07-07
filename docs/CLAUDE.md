# CLAUDE.md

## What this is

**Dance App** — an iPad-native app for dancers learning choreography from video.
Load a video (TikTok/YouTube link or local file), detect tempo, set the "1"
count, then scrub, loop, slow down, and drill sections with a DJ-board-style
timeline. Think "DJ deck for dance practice."

## Platform & stack

- **Target:** iPadOS 17+, iPad only, landscape-first. Native Swift.
- **UI:** SwiftUI for app shell/panels; UIKit-backed views (via
  `UIViewRepresentable`) where we need fine-grained gesture + render control
  (the scrub wheel, waveform strip, right-edge speed gesture).
- **Video:** AVFoundation (`AVPlayer`, `AVPlayerItem`) for playback.
  `AVPlayer.rate` for speed changes with `audioTimePitchAlgorithm = .timeDomain`
  (preserves pitch at practice speeds).
- **Audio analysis:** `AVAudioEngine` + Accelerate/vDSP. Waveform peaks
  precomputed from the extracted audio track. Tempo detection via onset
  detection + autocorrelation (custom, vDSP) — no server dependency.
- **Scrub audio ("DJ scratch"):** separate `AVAudioEngine` graph with a
  varispeed node reading the extracted audio file, driven by scrub velocity.
  Video player stays muted while scrubbing.
- **No backend.** Everything on-device. Link ingestion is the only network
  feature.

## Project layout (once Xcode project exists)

```
DanceApp/
  App/              # entry point, app-level state, DI
  Features/
    Import/         # link/file/share-sheet ingestion, download, ATS notes
    Player/         # video view, zoom, playback engine wrapper
    Timeline/       # scrub wheel, waveform strip, beat grid rendering
    Beats/          # tempo detection, beat grid model, count labeling
    Markers/        # user markers, snap buttons, A/B loop
    SpeedControl/   # right-edge speed gesture
    Calibration/    # Bluetooth latency offset
  Core/
    AudioAnalysis/  # waveform peaks, onset/tempo detection (vDSP)
    Media/          # asset extraction, caching, file management
    Sync/           # master clock, latency-compensated time mapping
  Resources/
```

## Core domain concepts

- **Master clock:** one source of truth for playhead time (`CMTime`). The
  video player, scrub wheel, waveform, and beat grid all render from it.
  Never let two components each own "current time."
- **BeatGrid:** `firstBeatTime` (the user-set "1") + `bpm` (detected, user
  adjustable) → derives all beat times. Counts cycle 1–8; half-beats are
  "and" counts. Grid is a pure function of `(firstBeatTime, bpm, t)`.
- **Latency offset:** a single signed offset (ms) applied when *displaying*
  audio-synced UI vs. Bluetooth audio output. Video/beat visuals shift by
  the calibrated offset; the media timeline itself is never modified.
- **Markers:** timestamped, ordered, snappable. A/B loop is just two special
  markers plus a loop flag.

## Conventions

- Swift 5.10+, strict concurrency where feasible. `@MainActor` for UI state;
  audio analysis off the main actor.
- One feature = one directory under `Features/`, each with its own view(s) +
  observable model. Cross-feature communication goes through app-level state
  in `App/`, not feature-to-feature imports.
- Time is always `CMTime` or seconds as `Double` — pick `CMTime` at
  boundaries with AVFoundation, `Double` (seconds) inside our own models.
  Never frames, never sample counts, in feature code.
- Gestures that affect playback must be interruptible and never fight the
  transport: scrubbing pauses, releasing resumes prior state.
- 60fps (ProMotion: 120fps) target on the timeline. No SwiftUI body
  re-evaluation per frame — use `TimelineView`/`CADisplayLink` + Canvas or
  CALayer drawing for the wheel and waveform.

## Build & run

- Project: `dance-app/dance-app/dance-app.xcodeproj` (nested path), scheme
  `dance-app`, sources in `dance-app/dance-app/dance-app/` with
  filesystem-synced groups (new files are picked up automatically).
- Build (see PROJECT_STATE.md → Environment quirks for why generic):
  `cd dance-app/dance-app && xcodebuild -project dance-app.xcodeproj -scheme dance-app -destination 'generic/platform=iOS Simulator' build`
- Test on real hardware early — Bluetooth latency calibration and gesture
  feel cannot be validated in the simulator.

## Legal/practical note on link ingestion

Downloading from TikTok/YouTube violates their ToS in most cases. The
supported paths are: local file import, Photos picker, share-sheet extension,
and paste-a-link where the user provides a direct video URL. Anything beyond
that is a product/legal decision — flag it, don't just build it.

## Key docs

- `ROADMAP.md` — phases and what's deferred
- `MILESTONES.md` — concrete milestones with acceptance criteria
- `PROJECT_STATE.md` — living status doc; **update it at the end of any
  session that changes project state**
