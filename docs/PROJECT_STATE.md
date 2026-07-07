# Project State

> Living document. Update at the end of any session that changes project
> state. Newest entries at the top of the log.

## Status

**Phase:** 3 — Practice tools
**Current milestone:** M5 — Markers & A/B loops (built; wiring +
persistence + rendering verified in sim, loop timing/feel need hardware).
M4 built (haptics + gesture feel need hardware). M3 feel-tuned per user
feedback (snap-don't-chase scratch, heavy wheel damping — see memory + code
comments). M2 verified by user. M1 leftover: share-sheet extension.
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

## M4 status (Speed control & count-off)

New since M3:
- `Features/SpeedControl/SpeedControlView.swift` — right-rail
  `SpeedRail` (chevron + SPEED + live % readout) with a UIKit
  long-press-then-drag catcher: hold 0.12 s engages, 24 pt of inward
  travel per 5% step, snapped and haptic-ticked (UIImpactFeedbackGenerator
  — silent in sim), clamped 25–100%. Rate holds after release and
  persists in the sidecar.
- `Features/SpeedControl/CountOffPlayer.swift` — "5, 6, 7, 8" ticks as
  sine clicks padded to exactly one beat interval each, queued
  back-to-back on an AVAudioPlayerNode for sample-accurate spacing at any
  practice rate; first tick accented (1.5 kHz vs 1 kHz).
- `AppState.togglePlayPause()` — with count-off enabled + a grid: snaps
  the playhead to the nearest beat and counts *into its 8-count position*:
  the run ends one count before the playhead's count, starts on 5 or 1
  (shortest run ≥ 3 counts), e.g. playhead on 1 → "5 6 7 8", on 2 →
  "5 6 7 8 1", on 8 → "5 6 7", on 6 → "1 2 3 4 5". Ticks accent 1 and 5;
  spacing is beatInterval/rate with absolute-deadline scheduling
  (ContinuousClock) so playback lands on the beat. Tapping during the
  count cancels it. Sequence logic verified for all 8 targets offline.
- `PlaybackEngine.setRate` — 0.25–1.0, applied live while playing
  (`playImmediately(atRate:)` on play), pitch preserved via `.timeDomain`.
- Music count-in option (music-note toggle next to the metronome, only
  active when count-off is on): playback starts N counts before the
  playhead and plays through the countdown. The wheel holds centered on
  the target (red playhead) while a yellow playhead shows actual playback
  catching up; when they meet, the wheel resumes following. Falls back to
  ticks-only when there isn't enough media before the playhead.
- Speed gesture grabs anywhere along the right edge (rail + a 44 pt strip
  over the video's right edge, full height). % HUD rides just left of the
  finger. Fine mode: finger near the rail → vertical drag = 1% steps;
  slid inward past 12 pt → coarse 5% snaps.
- Video overlays: big count-off numeral; finger-tracking % HUD. Transport:
  metronome + count-in-music toggles, tappable % label resets to 100.
- Sidecar gains `playbackRate` + `countOffEnabled` (optional fields —
  old files still decode).

Checklist:
- [x] Right-edge hold + drag inward, 5% snaps, haptic per snap
- [x] On-screen rate indicator while active; rate persists
- [x] Pitch-preserved audio at all rates
- [x] Count-off "5,6,7,8", one beat per count at current rate, aligned
      to the grid (playhead snaps to nearest beat first)
- [ ] The real "done when": one-handed mid-playback speed change without
      looking away, count-off lands exactly on the "1" — needs hardware
      (haptics don't fire in sim; count-off visual/audio sync within
      ~10 ms assumed from Task.sleep, verify on device).

## M5 status (Markers & A/B loops)

New since M4:
- `Features/Markers/Marker.swift` — `Marker` (id/time/name, Codable) +
  `MarkersModel` (@Observable): user-ordered `markers`, `loopA`/`loopB`,
  `loopEnabled`, `loopRange` (valid only when B > A). Owned by `AppState`.
- `Features/Markers/MarkerRailView.swift` — the real left rail (replaces the
  M1 placeholder that lived in `MainShellView`): eject, a scrolling list of
  marker snap chips (name + m:ss; tap = seek to marker), an orange "Mark"
  button, and the A/B loop block (A/B set tiles showing their times, a Loop
  toggle that lights green when armed, Clear loop). Rename via an alert;
  reorder (Move Up/Down) and delete via each chip's context menu. Rail
  widened 72 → 112 pt.
- `AppState` markers/loops API: `addMarkerAtPlayhead` (default name = lowest
  unused integer), `snapToMarker`, `renameMarker`, `deleteMarker`,
  `moveMarker(by:)`, `setLoopA`/`setLoopB` (auto-normalized so A precedes
  B), `toggleLoop`, `clearLoop`. Loop playback: `PlaybackEngine.onTick`
  (fired from the periodic time observer, gated off while scrubbing) drives
  `handlePlayheadTick` → wraps at B (30 ms guard band) back to A. With
  count-off on, each loop pass runs the count-off into A (reuses
  `startCountOff`, so the music-count-in variant works too); otherwise it's
  a plain seek that keeps playing.
- Scroller (`ScrubWheelView`): renders the A/B loop as a translucent green
  region (brighter when armed) with green A/B boundary lines + labels, and
  markers as orange full-height lines with a name chip at the bottom (clear
  of the top beat-count labels). Wheel long-press (0.4 s, stationary) drops
  a marker at the playhead with a haptic. `WheelRenderState` gained
  `markers`/`loop`/`loopActive`.
- Sidecar gains `markers`, `loopA`, `loopB`, `loopEnabled` (all optional —
  pre-M5 files still decode).

Checklist:
- [x] Set a marker at the playhead (rail "Mark" button + wheel long-press)
- [x] Left rail marker buttons; tap snaps the playhead to the marker
- [x] Markers rename / reorder / delete; rendered on the scroller
- [x] A/B loop: set A, set B, loop toggle; loop respects the count-off
      option (counts back in each pass when count-off is on)
- [x] All of it persists per video
- [x] Verified: builds; end-to-end in the sim via planted session — markers
      + active A/B loop restored, rail chips/tiles/toggle render, scroller
      draws the green loop region + orange marker chips
- [ ] The real "done when": full practice loop on hardware — mark verse →
      snap → set A/B around the hard part → loop at 60% with count-off,
      loop wrap landing cleanly on the beat (timing needs a device, like
      M4 count-off).

## Next up

1. Hardware pass: wheel feel (τ=0.18, dead-stop thresholds), speed
   gesture (24 pt/step), count-off timing, haptics, frame rate, and M5
   loop-wrap timing (does the wrap land on the beat at 60%?).
2. Validate M2 tempo detection against real dance videos (5-video test).
3. M1 leftover: share-sheet extension target (create in Xcode).
4. Start M6: Bluetooth latency calibration & ship prep.

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

### 2026-07-06 (third session)
- Built M5 (markers & A/B loops), moving into Phase 3. New
  `Features/Markers/` (Marker + MarkersModel, MarkerRailView); markers/loops
  API + loop playback (`PlaybackEngine.onTick` → `handlePlayheadTick`) in
  AppState; scroller renders loop region + markers; wheel long-press drops a
  marker; sidecar extended (optional fields). Left rail is now real
  (replaced the M1 placeholder), widened to 112 pt.
- Verified in sim: builds clean; planted a session with two markers and an
  armed A/B loop → restored correctly, rail chips/A-B tiles/green Loop
  toggle render, scroller draws the green loop band + orange marker chips.
  Loop-wrap timing at practice rates still wants a device.

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
