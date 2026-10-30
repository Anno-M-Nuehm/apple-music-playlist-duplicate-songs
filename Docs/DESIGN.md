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
Both are used, each where it is strong:

- **ScriptingBridge (SB)** drives playlist listing, app resolution,
  library switching (via NSWorkspace), and entry removal
  (`SBElementArray.removeObject(at:)`, descending indexes, count
  verification). Typed declarations live in a checked-in minimal
  header (`Generated/Music.h`); SB resolves the selectors against
  Music's sdef at runtime. Because SB objects never actually belong to
  the header's classes, typed views are created with `unsafeBitCast` —
  the same compile-time-lens-only semantics ObjC gets implicitly.
- **NSAppleScript (one bulk script)** fetches a playlist's track
  metadata in a **single Apple event**: a plain script (no handler)
  loops `every track` inside Music and returns a delimited record
  stream. This is the only way to avoid SB's fatal chattiness — SB
  property reads cost one Apple event per track per property (minutes
  on large playlists). The script text interpolates ONLY the validated
  numeric playlist ID; no user data ever touches script text (see
  SECURITY.md).
- The bulk script runs without an `on run` handler and is executed via
  `executeAndReturnError` — the earlier parameterized-handler approach
  (`«event aevtpsbr»`) failed with error -1708 (errAENoSuchHandler)
  because the subroutine event must be addressed to the script's own
  context, not the target application.

### Duplicate detection & scan model
- Detection priority: persistent ID, then normalized
  title+artist+album with duration clustering (± tolerance, default
  2 s, from config.json). Groups from both strategies that share
  entries are merged (union-find, deduplicated by entry ID).
- Persistent IDs that fail to parse get unique synthetic IDs — never
  fabricated values, which caused phantom duplicate groups.
- **Lazy scan**: launch lists playlists only; a playlist's tracks are
  fetched exactly once, on selection (timeout-bounded at 20 s), and
  the duplicate count is cached for the session. No upfront
  full-library scan — that took minutes on real libraries.

### Removing duplicates when identical entries share a track ID
Music cannot delete "the second occurrence of track X" by ID — both
occurrences have the same ID. Entries are therefore identified by
their **1-based playlist index** from the bulk fetch, and removal
deletes by descending index via `SBElementArray.removeObject(at:)`,
guarded by a count check before and after. Only one playlist is ever
referenced.

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
