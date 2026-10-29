# Testing

## Automated tests

Run in Xcode with scheme **PlaylistDeduplicator**, `⌘U`
(`Product ▸ Test`), or from the command line:

```bash
xcodebuild test \
  -project PlaylistDeduplicator.xcodeproj \
  -scheme PlaylistDeduplicator \
  -destination 'platform=macOS'
```

### Suites

- `DuplicateDetectorTests` — detection edge cases: persistent-ID
  duplicates, metadata fallback within duration tolerance, live vs.
  studio (60 s apart) NOT matched, same title different albums NOT
  matched, missing metadata NOT matched against each other,
  case/whitespace-insensitivity, configurable tolerance, triple
  occurrences, ID+metadata group merging.
- `ConfigStoreTests` — config.json parsing, defaults, overrides.
- `ReportExporterTests` — CSV quoting/escaping, Markdown structure,
  configured columns.
- `KeychainStoreTests` — missing key returns nil (no crash).
- `MockMusicIntegrationTests` — full scan → detect → select → remove
  flow against the mocked Music layer, including: only the selected
  playlist is modified, other playlists untouched, pre-selection is
  "all but first", toggle/clear selection, excluded playlist names,
  error surfacing.

The real Music integration (`AppleScriptMusicService`) is intentionally
not unit-tested against a live Music library; its scripts are static
strings and its logic is exercised through the protocol in the mock
tests. The UAT checklist below covers it end-to-end.

## UAT checklist (manual, ~15 minutes)

Run with a real Music library containing at least: a playlist with an
exact duplicate, a playlist with a live + studio version of one song,
a smart playlist, and an empty playlist.

1. **First launch & permission**: app opens; macOS asks to control
   Music; granting allows the scan to complete.
2. **Permission denied path**: deny automation, relaunch → clear error
   message, app does not crash; granting in System Settings fixes it.
3. **Playlist listing**: pane 1 lists all user playlists with correct
   track counts; special playlists (Music, Podcasts…) are excluded.
4. **Smart playlists**: smart playlists are not listed (default config).
5. **Duplicate flags**: pane 2 lists only playlists containing
   duplicates, each with a red badge showing the group count.
6. **Clean playlist**: selecting a clean playlist shows "No duplicates"
   in pane 3.
7. **Duplicate groups**: selecting a flagged playlist shows groups
   grouped by track; the kept entry is marked, all others pre-checked
   for removal.
8. **Pre-selection correctness**: for a triple occurrence, exactly two
   entries are pre-selected.
9. **Live vs. studio**: a playlist with live + studio versions of the
   same song is NOT flagged as duplicates.
10. **Toggling**: unchecking an entry removes it from the removal set;
    "Select all but first" / "None" work per group.
11. **Removal**: clicking "Remove Selected" removes exactly the checked
    entries from the selected playlist in Music; verify in Music.
12. **Isolation**: after removal, verify no other playlist changed and
    no file was deleted from disk (e.g. on the NAS share).
13. **Concurrent-modification safety**: edit the playlist in Music
    between scan and removal → app reports the mismatch, removes
    nothing.
14. **Export CSV**: File ▸ Export Report… → CSV opens a save panel,
    writes a valid CSV with all groups (verify in Numbers/Excel).
15. **Export Markdown**: same for Markdown; check the report renders.
16. **Keyboard**: Tab/arrows/Space navigate and toggle; ⌘E opens export.
17. **Dark mode**: switch appearance → all panes render correctly.
18. **Offline AI assist**: with no API key in Keychain and network off,
    the app is fully usable and no errors appear.
