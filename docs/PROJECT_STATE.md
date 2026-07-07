# Project State

> Living document. Update at the end of any session that changes project
> state. Newest entries at the top of the log.

## Status

**Phase:** 2 — The deck
**Current milestone:** M3 — The scrub wheel (built; feel-tuning needs real
hardware). M2 verified by user. M1 leftover: share-sheet extension.
**Last updated:** 2026-07-06

## What exists

- Xcode project at `dance-app/dance-app/dance-app.xcodeproj` (note the
  nested path; scheme `dance-app`, bundle id `micahlai.dance-app`).
  iPad-only, landscape-only, deployment target **iPadOS 17.0** (decided —
  see log), filesystem-synced groups so new files are picked up
  automatically.
- Source under `dance-app/dance-app/dance-app/`:
  - `App/AppState.swift` — app-level state: current `VideoDocument` +
    `PlaybackEngine`
  - `Core/Media/VideoDocument.swift`, `Core/Media/MediaImporter.swift` —
    import (copy into Application Support/Videos) + audio extraction to m4a
  - `Features/Player/PlaybackEngine.swift` — AVPlayer wrapper, master
    playhead state (`currentTime`/`duration`/`isPlaying`)
  - `Features/Player/ZoomableVideoView.swift` — UIScrollView-backed pinch
    zoom + pan, double-tap reset
  - `Features/Import/ImportView.swift` — Photos picker, Files importer,
    paste-a-direct-link (downloads via URLSession)
  - `Features/Shell/MainShellView.swift` — practice layout: marker rail
    (placeholder + eject), video center, speed rail (placeholder),
    transport bar with play/pause + seek slider (stand-in for M3 wheel)

## M1 checklist status

- [x] iPad-only landscape shell with placeholder panels
- [x] Photos picker and Files import
- [ ] Share-sheet extension — **deferred**: needs a new Xcode target;
      create it in Xcode (File > New > Target > Share Extension), not by
      hand-editing pbxproj
- [x] Paste-a-link for direct video URLs
- [x] Play/pause, seek, pinch+pan zoom, double-tap reset
- [x] Audio extracted to m4a next to video on import
- [~] Verified: builds, installs, and launches on the iPad Pro 12.9 sim;
      import screen renders. Import→playback with a real video still needs
      a manual tap-through (Photos/Files/link → play, seek, pinch zoom).

## Environment quirks (this Mac)

- Xcode 26.6 with iOS 26.5 SDK, but the only simulator runtime is
  **iOS 17.2** — named-destination builds fail with "iOS 26.5 is not
  installed". Build with:
  `xcodebuild -project dance-app.xcodeproj -scheme dance-app -destination 'generic/platform=iOS Simulator' build`
  then install/launch via `simctl` on the iPad Pro 12.9 (6th gen) sim
  (UDID `A0E174E7-B826-4DEE-9394-820CE3C6484C`), or install a current
  simulator runtime in Xcode > Settings > Components.
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` is on (Xcode 26 template):
  everything is MainActor-isolated by default; analysis code that must run
  off-main (M2 waveform/tempo) needs explicit `@concurrent`/`nonisolated`.

## M2 status (Tempo & the "1")

New since M1:
- `Core/AudioAnalysis/AudioAnalyzer.swift` — waveform peaks (vDSP, cached
  as `<id>.waveform.json`) + tempo detection: spectral-flux onset envelope
  (FFT via vDSP), detrended, autocorrelated over 60–200 BPM with harmonic
  scoring + mild 120-BPM log-normal prior, parabolic lag refinement, and a
  comb-filter beat-phase estimate for the suggested anchor.
- `Features/Beats/` — `BeatGrid` (pure function of firstBeatTime + bpm;
  1–8 counts, "&" half-counts, negative-time safe), `BeatsModel`,
  `BeatWorkbenchView` (8s scrolling waveform strip with beat grid + labels
  + center playhead, Canvas @30fps; controls row: BPM ±1/±0.1/½×/2×,
  "Set 1" at playhead, ±10ms nudge, shift-by-beat).
- `Core/Media/DocumentStore.swift` — sidecar `<id>.state.json` per video
  (filenames, not absolute paths); most-recent session restored on launch.

Checklist:
- [x] Waveform peaks off-main + cached
- [x] BPM detection with confidence, editable
- [x] "Set the 1" UI with nudges
- [x] Beat grid with 1–8 and "and" counts
- [x] Grid/BPM/anchor persist per video (verified in sim container)
- [x] Verified: offline harness — 4 synthetic click tracks (75/96/120/140
      BPM) all detected within 0.3 BPM, conf 0.94–0.98, phase < 40 ms;
      end-to-end in simulator via planted session (detected 120.1 · 98%,
      grid rendered, sidecar + waveform cache written)
- [ ] The real "done when": 5 real dance videos (studio choreo, TikTok w/
      talking intro, live performance, no-drums, tempo drift) → correct
      grid in < 30 s. Needs a human with real footage.

## M3 status (The scrub wheel)

New since M2:
- `Features/Timeline/ScrubWheelView.swift` — `WheelView` (UIKit): pan to
  scrub with exponential-decay inertia (τ≈0.5s), pinch to zoom the time
  scale (1.5–40 s/screen), CADisplayLink rendering at 60–120fps via Core
  Graphics. Draws waveform (toggleable), beat grid (numbered counts, "&"
  half-ticks with labels when zoomed in past 12 s/screen, blue "1"),
  shaded out-of-media regions, fixed center playhead. Replaced the M2
  waveform strip and the transport slider.
- `Features/Timeline/ScrubAudioEngine.swift` — DJ-scratch audio:
  `AVAudioSourceNode` chases the finger position through pre-decoded mono
  samples (signed rate, so backwards works — varispeed can't), linear
  interpolation, rate capped at 3× natural, unfair-lock-guarded state.
  Toggleable from the transport bar.
- `PlaybackEngine` scrub API: `beginScrub` (remembers play state, pauses),
  `scrub(to:)` (throttled AVPlayer seeks — one in flight, latest wins,
  40 ms tolerance while scrubbing), `endScrub` (precise seek, resumes if
  it was playing). Periodic time observer is gated off while scrubbing so
  the wheel owns the playhead.
- Transport bar slimmed: play/pause, time, waveform + scrub-audio toggles.

Checklist:
- [x] Inertial wheel driving the playhead
- [x] Bidirectional sync (plays → wheel follows; touch takes over,
      release resumes prior state; touch during coast keeps the session)
- [x] Beat ticks with numbered counts + smaller "and" ticks
- [x] Waveform overlay toggle
- [x] Timeline pinch zoom
- [x] Audible scrub via custom source-node graph
- [ ] The real "done when": 120fps sustained on a ProMotion iPad, scratch
      latency/feel, no drift after 10 min — needs real hardware + hands.
      Simulator only confirms rendering and wiring.

## Next up

1. Hardware pass on the wheel: gesture feel, inertia constants (τ, snap
   threshold), scratch chase window (60 ms), frame rate.
2. Validate M2 tempo detection against real dance videos (5-video test).
3. M1 leftover: share-sheet extension target (create in Xcode).
4. Start M4: right-edge speed gesture + count-off.

## Open decisions

- [ ] Link ingestion scope: paste-a-link with direct URLs only, or invest in
      TikTok/YouTube handling? (ToS concerns — see CLAUDE.md.) Current
      build: file/Photos/direct URLs only, with an explanatory footnote in
      the import UI.
- [x] Tempo detection: custom vDSP pipeline (no external deps) — built and
      validated in M2. Revisit only if real-video accuracy disappoints.
- [x] Persistence: Codable JSON sidecar files per video, storing filenames
      (container-relative). SwiftData not needed.

## Known risks

- **Scrub wheel feel** is the product. Prototype it on hardware early (can
  pull forward from M3 as a spike if M2 drags).
- **Tempo detection on real dance videos** (crowd noise, talking intros,
  music starting mid-video) is much harder than on clean tracks. The "set
  the 1" manual fallback must be excellent.
- **A/V sync while scrubbing:** keeping video frame, scrub audio, and beat
  ticks aligned under fast wheel motion needs a single master clock design
  from day one (see CLAUDE.md → Core domain concepts). `PlaybackEngine` is
  that single owner today — keep it that way.

## Session log

### 2026-07-06 (second session)
- Xcode project created from template; restructured settings: iPad-only
  (`TARGETED_DEVICE_FAMILY = 2`), landscape-only, deployment target lowered
  26.5 → 17.0 (only iOS 17.2 sim runtime installed; matches roadmap).
- Implemented M1 minus share-sheet extension: import (Photos/Files/link),
  audio extraction, zoomable playback, layout shell, transport bar.
- Docs moved into `docs/`.

### 2026-07-06
- Created project scaffold: CLAUDE.md, ROADMAP.md, MILESTONES.md,
  PROJECT_STATE.md. No code yet.
