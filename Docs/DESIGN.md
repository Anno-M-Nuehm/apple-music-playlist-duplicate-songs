# Design — Playlist Deduplicator

## Architecture: MVVM (justified)

The app is state-driven: the playlists list, duplicate counts, per-group
selection state, and removal progress all must update the UI reactively.
SwiftUI + `@Observable` view models give this for free, keep the Music
scripting layer mockable behind protocols, and keep duplicate detection
as pure, synchronous, unit-testable logic with no UI dependency.
Classic MVC would push state management into controllers and fight
SwiftUI's declarative model, so MVVM was chosen.

```
SwiftUI Views (3 panes, Help, Export sheet)
        ▲ environment objects
ViewModels: LibraryViewModel, DuplicationViewModel
        ▲ MusicLibraryService protocol
Music integration: AppleScriptMusicService (real) | MockMusicService (tests)
        ▲
Music app (Apple Events)
Core (pure logic): DuplicateDetector, ReportExporter, models
Support: ConfigStore (config.json), KeychainStore, AIAssistClient (optional)
```

## Object model

- **Track** — persistentID, title, artist, album, duration, location.
- **Playlist** — id, name, trackCount, isSmart.
- **PlaylistEntry** — one playlist position: (playlistID, 1-based index, Track).
  The same track twice ⇒ two entries with the same `track`. This models
  Music's playlist reality, where identical tracks are indistinguishable
  by ID but distinguishable by position.
- **DuplicateGroup** — `keep` (first occurrence) + `removals` (all others).

## Decision rationale

### ScriptingBridge vs. NSAppleScript
Chosen: **NSAppleScript with parameterized handlers**.
- ScriptingBridge (`SBApplication`) against Music is brittle: the Music
  scripting dictionary has long-standing bugs, SB property access is
  extremely chatty (one Apple event per property per track — fatal for
  10k+ tracks), and `SBElementArray` deletion of same-track duplicates
  is unreliable.
- NSAppleScript lets us pull *all* tracks of a playlist with their
  properties in a **single Apple event** (record-built string output),
  which is the batching strategy that keeps 10k+ track libraries fast.
- Security: every script is a static source string using
  `on run {param}` positional parameters. No library data (names,
  titles, paths) is ever interpolated into script text — only the
  numeric playlist ID and integer indexes are passed, and as typed
  Apple event descriptors. This eliminates AppleScript injection.
  See SECURITY.md.

### Removing duplicates when identical entries share a track ID
Music cannot delete "the second occurrence of track X" by ID — both
occurrences have the same ID. Workaround: entries are identified by
their **1-based playlist index** (from the batched fetch), and removal
deletes `track idx of playlist` in one script, with indexes passed in
**descending order** (no index shifting), guarded by a before/after
track-count check inside the same script. On any mismatch the script
returns "MISMATCH" and nothing is committed — the app surfaces an
error instead. Only one playlist is ever referenced.

### Duplicate matching strategy
1. Same persistent ID ⇒ same track ⇒ duplicate (highest confidence).
2. Fallback: normalized title + artist + album equal AND duration
   within ±`durationToleranceSeconds` (default 2 s, from config.json).
   Duration clustering prevents live (260 s) vs. studio (200 s)
   versions of the same title from being merged.
   Groups from both strategies that share an entry are merged
   (union-find), so an ID-duplicate plus a metadata-duplicate of the
   same song forms one group.
3. Tracks with empty titles never match by metadata (prevents
   "missing metadata" tracks from collapsing into one giant group).

### Performance
One Apple event per playlist fetch, one per removal, dedup entirely
in memory. All scripting runs on a dedicated serial queue; view models
are `@MainActor` and `async/await` onto that queue, so the UI never
blocks. Scanning a 10k-track library is dominated by a handful of
batched Apple events, not 10k round-trips.

### AI assist (optional module)
For entries whose track has an empty/invalid `location`, the app can
ask a configured HTTPS endpoint to re-match metadata. Provider/model/
endpoint come from `config.json`; the API key comes from the macOS
Keychain at call time. Only title/artist/album are sent. If disabled
in config, no key present, offline, or any error — the feature is
silently unavailable and the app is fully functional without it.

## Known limitations (stated explicitly)

- **Sandbox**: Apple does not publish a scripting-targets entitlement
  for Music. Controlling Music therefore requires either the
  `com.apple.security.temporary-exception.apple-events` entitlement
  (App Store reviewers accept it case-by-case for Music utilities) or
  Developer ID distribution with sandbox off. Both paths ship in the
  repo (see BUILD.md).
- Music must be running; the app launches it via Apple Events if not.
- Smart playlists cannot be modified by any external tool (Music
  itself disallows it); they are excluded from scanning by default
  (`config.json → playlists.includeSmartPlaylists`).
