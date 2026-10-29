# Playlist Deduplicator (macOS)

A native macOS app (Swift + SwiftUI) that finds and removes duplicate
tracks **within a single Apple Music playlist** — never files, never
other playlists, never library-wide changes.

## App Store–style description

Playlist Deduplicator keeps your Apple Music playlists tidy. It scans
your library, flags every playlist that contains the same track more
than once, and shows the duplicates grouped by song — with all but one
occurrence pre-selected for removal. One click cleans the playlist,
and a safety check makes sure nothing outside that playlist ever
changes. Export what it found as a CSV or Markdown report, and rest
easy: no analytics, no telemetry, your music library stays exactly
where it is.

## Features

- Three-pane UI: all playlists · playlists with duplicates (badge
  counts) · duplicate groups of the selected playlist.
- Detection: persistent track ID first; fallback title + artist +
  album + duration ±2 s (configurable in `config.json`). Live vs.
  studio versions are correctly kept apart.
- Batched Apple Events — handles 10k+ track libraries without
  blocking the UI.
- Duplicate reports as CSV or Markdown.
- Optional AI assist for tracks with missing file locations
  (anonymized metadata only, HTTPS only, Keychain-held credential).
- Full keyboard accessibility, dark mode, native HIG look.

## GDPR / Austrian DSG statement

This app collects **no telemetry, no analytics, and no usage data**,
and includes no crash reporting. No personal data leaves the device.
The only network communication is the strictly optional AI-assist
feature: if (and only if) the user configures it, the app sends the
title, artist, and album of a track — nothing else — over HTTPS to the
endpoint the user configured. No names, library paths, persistent IDs,
or file locations are transmitted. In its default state the app makes
no network connections at all. Because nothing is collected or
transmitted, no data-processing agreement under Art 28 DSG is required
for normal use; if AI assist is enabled, the chosen provider's terms
apply to those three metadata fields.

## Documentation

- [DESIGN.md](Docs/DESIGN.md) — architecture and decisions
- [BUILD.md](Docs/BUILD.md) — build & install manual
- [TESTING.md](Docs/TESTING.md) — test suite + UAT checklist
- [USER_MANUAL.md](Docs/USER_MANUAL.md) — usage guide
- [SECURITY.md](Docs/SECURITY.md) — threat-model review

## Status of this deliverable

Complete source code, tests, assets, and docs. The `.xcodeproj` is
generated from `project.yml` (see BUILD.md) because the project was
authored without Xcode; run `xcodegen` once to materialize it, or let
the Swift Package fallback guide you. Build requires macOS 13+ and
Xcode 15+ (Swift 6 concurrency used throughout).
