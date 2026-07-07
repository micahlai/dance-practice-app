# Milestones

Each milestone is shippable-to-TestFlight-ish on its own and has concrete
acceptance criteria. Order matters — later milestones assume earlier ones.

---

## M1 — Video in, video plays

**Goal:** Any video the user cares about is on screen and playable.

- [ ] iPad-only Xcode project, landscape shell with placeholder panels
      (video center, timeline bottom, marker rail left, speed zone right)
- [ ] Import via Photos picker and Files
- [ ] Share-sheet extension accepts video files and URLs
- [ ] Paste-a-link flow for direct video URLs (see CLAUDE.md ToS note)
- [ ] Play/pause, tap-to-seek, pinch + pan zoom on the video
- [ ] Audio track extracted to a cached local PCM/M4A file on import

**Done when:** a video imported any of these ways plays with working zoom,
and its audio file exists in the cache.

---

## M2 — Tempo & the "1"

**Goal:** The app knows the beat and the user can correct it.

- [ ] Waveform peaks computed off-main-thread and cached
- [ ] BPM detection with confidence score; result editable
- [ ] "Set the 1" UI: tap on the beat / nudge buttons to anchor the downbeat
- [ ] Beat grid derives 1–8 counts and "and" half-counts from
      `(firstBeatTime, bpm)`
- [ ] Grid + BPM + anchor persist per video

**Done when:** on 5 test videos (studio choreo, TikTok with talking intro,
live performance, no-drums track, rubato/tempo-drift track) the user can get
a correct grid in under 30 seconds, even where detection fails.

---

## M3 — The scrub wheel

**Goal:** The signature interaction. Smooth or it doesn't ship.

- [ ] Bottom scroller with wheel/inertial physics driving the playhead
- [ ] Playhead ↔ wheel bidirectional sync (playing moves the wheel;
      touching the wheel takes over, releasing resumes prior play state)
- [ ] Beat ticks rendered on the scroller: numbered counts, smaller
      "and" ticks
- [ ] Waveform overlay toggle on the scroller
- [ ] Timeline zoom (pinch on scroller changes seconds-per-screen)
- [ ] Audible scrub (DJ scratch) toggle via varispeed audio graph

**Done when:** 120fps on ProMotion iPad while scrubbing with waveform on;
scrub audio pitch tracks wheel velocity; no drift between wheel, video
frame, and beat ticks after 10 minutes of use.

---

## M4 — Speed control & count-off

**Goal:** Drill sections slower without touching menus.

- [ ] Right-edge gesture: press-and-hold engages, dragging inward changes
      rate, snapping to 5% increments (25%–100%), haptic tick per snap
- [ ] On-screen rate indicator while gesture is active; rate persists
- [ ] Pitch-preserved audio at all rates
- [ ] Count-off option: audible + visual "5, 6, 7, 8" (one bar at current
      rate, aligned to the beat grid) before playback starts

**Done when:** speed can be changed mid-playback one-handed without looking
away from the video, and count-off lands exactly on the "1."

---

## M5 — Markers & loops

**Goal:** Structure the song into drillable sections.

- [ ] Set a marker at the playhead (button + wheel long-press)
- [ ] Left rail shows marker buttons; tap snaps playhead to marker
- [ ] Markers rename/reorder/delete; rendered on the scroller
- [ ] A/B loop: set A, set B, loop toggle; loop respects count-off option
- [ ] All of it persists per video

**Done when:** the full practice loop works: mark verse → snap to it →
set A/B around the hard part → loop at 60% with count-off.

---

## M6 — Latency calibration & ship

**Goal:** Beat visuals honest over Bluetooth; app ready for outsiders.

- [ ] Calibration flow: metronome plays, user taps on the beat, offset
      computed from median error; stored per audio route
- [ ] Offset applied to beat-visual rendering; auto-prompt when an
      uncalibrated Bluetooth route connects
- [ ] Gesture onboarding overlays (speed edge, wheel, marker rail)
- [ ] Memory/perf pass with a 10-minute 4K video
- [ ] Privacy manifest, App Store metadata, TestFlight build

**Done when:** external testers on AirPods report beat markers "feel on
beat," and a TestFlight build is live.

---

## Later milestones (unscheduled)

- **L1 Stem separation** — on-device source separation (Core ML); UI to
  solo/mute stems during practice
- **L2 Crowd noise removal** — cleanup pass for live-performance videos
- **L3 Percussion waveform** — drums-only waveform as an alternate scroller
  view (depends on L1)
