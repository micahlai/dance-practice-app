# Roadmap

Guiding principle: get the **practice loop** working end-to-end first
(load video → find the beat → scrub/loop/slow down), then layer on
precision tools, then audio intelligence.

## Phase 0 — Foundation

Project setup, video in, video out.

- Xcode project, iPad-only target, landscape layout shell
- Video import: Photos picker, Files, share-sheet extension, paste-a-link
- Basic playback: play/pause, seek, pinch-to-zoom on video
- Audio track extraction to local file (feeds everything in Phase 1)

## Phase 1 — The beat

Tempo is the spine of the app; everything downstream renders against it.

- Waveform peak extraction (vDSP), cached per asset
- Tempo (BPM) detection: onset detection + autocorrelation
- "Set the 1": user taps/drags to anchor the first downbeat; BPM fine-adjust
- Beat grid model: counts 1–8 and "and" half-counts, labeled

## Phase 2 — The deck

The DJ-board interaction layer. This is the product's feel — budget real
time for tuning, on real hardware.

- Bottom scrub wheel: smooth, inertial, wheel-like UI driving the playhead
- Beat markers rendered on the scroller (numbered counts + "and" ticks)
- Optional waveform overlay on the scroller
- Scrub audio playback (DJ-style audible scrubbing, toggleable)
- Right-edge speed gesture: hold + drag inward, snapping to 5% increments
- Count-off playback option (audible "5,6,7,8" before play)

## Phase 3 — Practice tools

- User markers: set/delete, left-side snap buttons to jump to each
- A/B loop markers with loop playback
- Bluetooth latency calibration (tap-to-beat test → stored offset per device)
- Per-video persistence: BPM, "1" anchor, markers, loop, speed

## Phase 4 — Polish & ship

- Onboarding for the non-obvious gestures (speed edge, wheel)
- Performance pass: 120fps timeline on ProMotion, memory with long videos
- App Store prep, privacy manifest, TestFlight

## Later (explicitly deferred)

Audio intelligence — expensive, model-dependent, not needed for the core loop:

- **Stem separation** (on-device model, e.g. Demucs-class via Core ML)
- **Crowd noise removal** for videos shot at performances
- **Percussion isolation** as an alternate waveform view (drums-only
  waveform makes counts far easier to see)

Also parked: iPhone layout, cloud sync, sharing marked-up videos.
