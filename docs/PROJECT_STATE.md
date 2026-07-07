# Project State

> Living document. Update at the end of any session that changes project
> state. Newest entries at the top of the log.

## Status

**Phase:** 0 — Foundation
**Current milestone:** M1 — Video in, video plays (mostly done; share-sheet
extension outstanding)
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

## Next up

1. Verify M1 end-to-end in the simulator/device with a real video.
2. Add the share-sheet extension target (in Xcode, not by hand).
3. Start M2: waveform peak extraction (vDSP) off the extracted m4a.

## Open decisions

- [ ] Link ingestion scope: paste-a-link with direct URLs only, or invest in
      TikTok/YouTube handling? (ToS concerns — see CLAUDE.md.) Current
      build: file/Photos/direct URLs only, with an explanatory footnote in
      the import UI.
- [ ] Tempo detection: fully custom vDSP pipeline vs. wrapping an existing
      library (e.g. aubio). Decide during M2 spike.
- [ ] Persistence: SwiftData vs. plain Codable JSON sidecar files per video.
      Leaning sidecar files (simple, exportable) — confirm at M2.
      Note: `VideoDocument` currently stores absolute URLs; switch to
      library-relative filenames before persisting (absolute paths break
      across app updates/reinstalls).

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
