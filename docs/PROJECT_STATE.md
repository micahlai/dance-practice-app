# Project State

> Living document. Update at the end of any session that changes project
> state. Newest entries at the top of the log.

## Status

**Phase:** 4 — Polish & ship
**Current milestone:** M6 — Latency calibration & ship (calibration flow +
per-route offset + beat-visual compensation + route auto-prompt + gesture
onboarding + privacy manifest all built & verified in sim; the ship items —
10-min 4K perf pass, TestFlight/App Store metadata — need a device + App
Store Connect). M5 (markers/loops) built, sim-verified. M4 built (haptics +
gesture feel need hardware). M3 feel-tuned per user feedback. M2 verified by
user. M1 leftover: share-sheet extension.
**New feature:** Recording/takes workspace and home take library implemented;
build and automated timing/export checks pass. Camera timing and iPad UI
interaction still require a manual/device pass.
**Last updated:** 2026-10-07

## What exists

- Xcode project at `dance-app/dance-app/dance-app.xcodeproj` (note the
  nested path; scheme `dance-app`, bundle id `micahlai.dance-app`).
  iPad-only, **all orientations** (adaptive layout — see log; was
  landscape-only through M6), deployment target **iPadOS 17.0** (decided —
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
  - `Features/Recording/` — camera capture, independent count-in/music
    timing, speed correction, camera/side-by-side/PiP compositions,
    persistent drafts, previews, system share sheet, and storage accounting.
    Home includes every saved take with camera + reference thumbnails.
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
- Mid-playback speed changes apply **live**: `setRate` uses
  `player.playImmediately(atRate:)` (not a direct `player.rate =`), which
  `automaticallyWaitsToMinimizeStalling` (on by default) would otherwise
  defer/ignore — this is why changing speed while playing appeared to do
  nothing.
- Reset-to-100%: in addition to the transport's tappable %, a floating
  `SpeedResetButton` (`⟲ NN%` capsule) sits at the video's bottom-right,
  just above the wheel; shown only when slowed, resets live.

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

## M6 status (Latency calibration & ship)

New since M5:
- `Core/Sync/LatencyStore.swift` — per-output-route signed offset (seconds)
  in UserDefaults, keyed by `portType|uid`; route name + wireless
  (BT/AirPlay) detection via `AVAudioSession.currentRoute`.
- `Features/Calibration/` — `LatencyCalibrator` (@Observable): a 100-BPM
  metronome (`ClickPlayer`, an `AVAudioPlayerNode` firing a sine click per
  beat off a CADisplayLink) while the user taps; offset = **median signed
  tap error** vs the nearest scheduled beat (folds route latency + the
  dancer's own bias into one "feels on beat" number). `CalibrationView` —
  sheet with a tap pad (registers on touch-down), live Taps/Offset readout,
  Start/Restart/Save (Save gated at ≥6 taps).
- `AppState` latency wiring: `latencyOffset` for the current route, an
  `AVAudioSession.routeChangeNotification` observer that reloads the offset
  and, on an **uncalibrated wireless route**, sets `showCalibrationPrompt`.
  `applyCalibration(offset:)` persists + applies live. Transport gained a
  `headphones` button (accent when the route is calibrated) to open the
  sheet; MainShellView presents the sheet + the "New audio output" alert.
- Beat-visual compensation: `ScrubWheelView` shifts only the **beat grid**
  drawing by `latencyOffset` (query window −offset, draw +offset) so ticks
  cross the playhead when the delayed audio is heard. Playhead, markers,
  loop, and the media timeline are untouched (per CLAUDE.md).
- `Features/Onboarding/OnboardingOverlay.swift` — first-run coach marks for
  the three non-obvious gestures (markers rail, speed edge, scrub wheel),
  gated by `@AppStorage("hasSeenOnboarding")`, dismissed with "Got it".
- `PrivacyInfo.xcprivacy` (app bundle root) — no tracking, no collected
  data, UserDefaults required-reason `CA92.1`. Confirmed copied into the
  built `.app`.

Checklist:
- [x] Calibration flow: metronome + tap-to-beat, median-error offset,
      stored per audio route
- [x] Offset applied to beat-visual rendering; auto-prompt when an
      uncalibrated wireless route connects (route observer wired; can't
      exercise a real BT route in the sim)
- [x] Gesture onboarding overlays (speed edge, wheel, marker rail)
- [x] Privacy manifest
- [x] Verified in sim: builds; app launches clean (route observer +
      latency init run without crashing; route name reads "Speaker");
      onboarding overlay renders on first run; calibration sheet renders
      with the live route name, tap pad, readout, and controls
- [ ] **Memory/perf pass with a 10-minute 4K video** — needs a device +
      real 4K footage (deferred).
- [ ] **TestFlight build + App Store metadata + Privacy manifest audit on
      a real archive** — needs signing + App Store Connect (deferred).
- [ ] The real "done when": external testers on AirPods report markers
      "feel on beat" + a live TestFlight build — needs hardware + TestFlight.
      Calibration offset sign convention (positive = tap late / audio
      delayed → grid drawn later) is assumed; confirm on a device with real
      BT latency.

## Next up

1. M6 ship items: archive + TestFlight build, App Store metadata, and a
   memory/perf pass with a 10-minute 4K video (all need device/App Store
   Connect). Confirm the latency offset sign on a real Bluetooth route.
2. Hardware pass: wheel feel (τ=0.18, dead-stop thresholds), speed
   gesture (24 pt/step), count-off timing, haptics, frame rate, M5
   loop-wrap timing (does the wrap land on the beat at 60%?), and frame
   interpolation feel (dissolve vs. judder at 25–50%, one-frame latency).
3. Validate M2 tempo detection against real dance videos (5-video test).
4. M1 leftover: share-sheet extension target (create in Xcode).

All six roadmap milestones (M1–M6) now have their engineering built; what
remains is device/hardware validation, real-footage testing, the
share-sheet extension, and the actual TestFlight/App Store submission.

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

### 2026-10-07 — Root README

- Added `README.md` with project setup, practice controls, recording and
  count-in/speed behavior, draft sharing/storage, architecture, and the
  repeatable verification command. Written in a separate documentation
  worktree on `docs/project-readme`; no app code changes in this worktree.
- README describes the implemented Photos/Files import UI and identifies
  physical-device and manual checks that remain outstanding.

### 2026-10-07 — Recording, drafts, and home take library

- Recording button next to Help opens a full-screen Record/Drafts workspace;
  home also opens drafts without needing a loaded reference.
- Front/back camera with portrait/landscape capture; practice playback and
  clicks are suspended when entering recording. Camera runs on a serial
  queue. No microphone capture: final videos use clean reference music.
- Music start and count-in landing are independently configurable. Shared
  count sequence and click synthesis preserve the practice 1–8 / & behavior.
  Pre-roll is added when counts precede the start of available music.
- Speed is set before capture (25–100%). Optional normalization scales the
  camera duration by that rate, restoring original music speed. Keeping the
  recording speed preserves music pitch with AVFoundation's time-domain
  algorithm. Reference layouts appear in live preview and final exports.
- Stop → composed preview → save draft or discard. Each draft atomically
  stores camera footage, its reference copy, and capture-time metadata under
  Application Support/Takes. Existing drafts survive reference switching.
  Original sources remain intact on preview/export failure or cancellation.
- Drafts open a composed preview and export MP4 through Apple's share sheet.
  Deletion requires confirmation. Home shows every saved draft, original
  reference preview/title, per-draft storage, and total draft storage.
- Verified: generic iOS Simulator build passes; standalone checks cover all
  eight landing counts at four speeds, all three layouts with/without speed
  correction, and stopping before music starts. Real rendered pixels verify
  reference placement and pre-roll visibility; spectral checks confirm a
  440 Hz soundtrack stays 440 Hz in slowed and normalized exports.
- Manual validation outstanding: iPad portrait/landscape and Dynamic Type
  UI, actual capture/audio sync (including Bluetooth), interruptions, camera
  permissions, low-storage behavior, and Photos/Files/AirDrop destinations.
  Simulator UI automation was unavailable in this session.
- Repeat automated export checks with `bash tests/run_recording_checks.sh`;
  uses Swift/AVFoundation plus locally installed ffmpeg, no app-library data.
- Follow-up layout pass: portrait recording settings share the outer scroll
  view, while landscape keeps a separately scrollable settings rail. The
  repeatable verification script passed, including pixel and pitch checks.

### 2026-07-07 (sixth session)
- Frame interpolation option: new
  `Features/Player/FrameInterpolationView.swift` — an MTKView overlay inside
  the zoomable video view (so pinch/pan carries it) fed by an
  `AVPlayerItemVideoOutput`; at every display refresh it cross-blends the two
  most recent decoded frames (CIFilter dissolve, Metal-rendered), doubling the
  apparent frame rate. Frame blending, not optical flow (which can't run
  real-time at 4K on-device); picture runs one source frame late while
  active. Blend fraction denominator is the *measured* host-time spacing of
  the last two frame arrivals, so it adapts to practice rate and to the
  irregular arrivals while scrubbing.
- Gating: only active while scrubbing or playing at < 100%
  (`AppState.frameInterpolationActive`); at 1× the plain AVPlayerLayer
  shows and the overlay is hidden + paused (no video-output cost when off).
  User toggle ("slowmo" icon in the transport bar, next to waveform),
  persisted via UserDefaults (`frameInterpolationEnabled`, default off).
- Overlay is transparent when it has no frame yet (and in letterbox regions)
  so activation never black-flashes; output re-attaches automatically when
  the player item changes and seeds the current frame immediately.
- Verified in sim: builds; launches clean with a restored session; slowmo
  toggle renders in the transport bar. The blended output itself (scrub /
  slow playback) can't be driven by sim automation — needs a hands-on check,
  and the blend feel (one-frame latency, dissolve vs. judder at 25–50%)
  belongs on the hardware-pass list.

### 2026-07-06 (fifth session)
- Responsive layout: unlocked orientation (Info.plist iPad orientations now
  all four, both build configs) and made `PracticeView` adapt via a
  `GeometryReader`. Landscape keeps the three-column layout
  (marker rail | video+controls | speed rail); portrait (height > width)
  drops the speed rail so the video takes the width — the speed gesture
  stays live on the video's right edge. `BeatControlsRow` is now a
  horizontal `ScrollView` (detected-BPM badge inline) so it never clips at
  narrow widths / split view.
- Verified in sim by rotating the device (osascript → Simulator): portrait
  renders cleanly (marker rail + full-width video, all controls reachable,
  no speed rail); landscape unchanged (speed rail present). Automation note:
  osascript key events to the Simulator work in this environment for
  rotate (Cmd+←/→); mouse-click automation still needs coordinates.
- Wheel/waveform sizing: new `Features/Timeline/WheelHandle.swift` — a slim
  grabber bar above the scrub wheel; drag it up/down to resize the wheel
  (64–340 pt) or tap the chevron to collapse to a compact 40 pt strip. Size
  + collapsed state persist via `@AppStorage` (`wheelHeight`,
  `wheelCollapsed`). Verified default / collapsed / tall renders in sim.
- Scrub-sound off: the transport's speaker toggle already muted scrub audio;
  now `scrubAudioEnabled` (and `showWaveform`) persist across launches
  (UserDefaults-backed), so "off" sticks. Note for testing: the simulator's
  cfprefsd caches `@AppStorage`/UserDefaults, so a host-side `defaults
  write` + immediate relaunch is unreliable — use launch-arg overrides to
  screenshot persisted-pref states.

### 2026-07-06 (fourth session)
- Speed follow-ups on M4: fixed mid-playback speed changes (setRate now uses
  `playImmediately(atRate:)` so they apply live even with
  automaticallyWaitsToMinimizeStalling on) and added the bottom-right
  `SpeedResetButton` above the wheel.
- Built M6 (latency calibration & ship), entering Phase 4. New
  `Core/Sync/LatencyStore` (per-route offsets), `Features/Calibration/`
  (tap-to-beat calibrator + sheet), `Features/Onboarding/` (first-run coach
  marks), `PrivacyInfo.xcprivacy`. AppState gained latency state + a route
  observer + auto-prompt; ScrubWheelView shifts the beat grid by the offset;
  transport gained a headphones (calibrate) button.
- Verified in sim: builds clean; app launches without crashing (route
  observer + latency init OK, route reads "Speaker"); onboarding overlay
  renders on first run; calibration sheet renders (live route name, tap pad,
  Taps/Offset readout, Start/Save); `PrivacyInfo.xcprivacy` confirmed inside
  the built `.app`. Deferred (need device/App Store Connect): 10-min 4K perf
  pass, TestFlight/App Store metadata, and confirming the offset sign on a
  real BT route.

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
- Speed follow-ups: fixed mid-playback speed changes (now
  `playImmediately(atRate:)` so they apply live) and added the bottom-right
  `SpeedResetButton` above the wheel (rendered at a planted 50% — capsule
  shows `⟲ 50%`; hidden at 100%). Sim can't drive the drag gesture (no
  accessibility/tap tooling), so gesture feel still wants a device.

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
