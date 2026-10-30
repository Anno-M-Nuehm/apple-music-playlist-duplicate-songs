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

## UAT checklist (manual, ~20 minutes)

Run with a real Music library containing at least: a playlist with an
exact duplicate (ideally one song three times), a playlist with a live
+ studio version of one song, a smart playlist, a folder-nested
playlist, and an empty playlist.

1. **First launch & permission**: app opens; macOS asks to control
   Music; granting allows the playlist list to load.
2. **Permission denied path**: deny automation, relaunch → clear error
   message, app does not crash; granting in System Settings ▸
   Privacy & Security ▸ Automation fixes it.
3. **Playlist listing**: left pane lists all playlists quickly
   (ordinary, smart, folder-nested) with track counts; special sources
   (Music, Movies…) are excluded; smart playlists are shown.
4. **Lazy scan**: nothing is pre-scanned at launch; the middle pane
   initially shows "Nothing flagged yet".
5. **Duplicate check on selection**: selecting a playlist scans just
   that playlist (a few seconds even for large ones) and shows its
   duplicate groups on the right.
6. **Clean playlist**: selecting a clean playlist shows no groups and
   the playlist is not flagged in the middle pane.
7. **Pre-selection correctness**: for a triple occurrence, exactly two
   entries are pre-selected; the keeper is marked with a checkmark and
   its checkbox disabled.
8. **All-but-one invariant**: after "Remove Selected", exactly one copy
   of each duplicate group remains in the playlist — verify in Music.
9. **Isolation**: after removal, verify no other playlist changed and
   no media file was deleted from disk.
10. **Live vs. studio**: a playlist with live + studio versions of the
    same song is NOT flagged as duplicates.
11. **Metadata fallback**: two copies of the same song with different
    persistent IDs (e.g. one Apple Music stream, one local file) ARE
    flagged.
12. **Toggling**: unchecking an entry removes it from the removal set;
    re-checking works; "Select all but first" / "None" per group.
13. **Smart playlist removal**: attempting removal from a smart
    playlist fails with a clear error (Music computes smart playlists
    from rules; removal is impossible by design) — no crash, no
    corruption.
14. **Refresh**: add a track to a playlist in Music directly, press
    ⌘R, reselect the playlist — the new track appears in the analysis.
15. **Export CSV**: File ▸ Export Report… → CSV writes a valid file
    (verify in Numbers/Excel).
16. **Export Markdown**: same for Markdown; check the report renders.
17. **Library switching**: choose a different .musiclibrary via the
    toolbar menu — Music opens it and the scan runs against it;
    "Current Music Library" returns to the open one; an unreachable
    copy falls back with an explanatory message.
18. **Keyboard**: Tab/arrows/Space navigate and toggle; ⌘R refresh, ⌘E
    export, ⌘? help.
19. **Dark mode**: switch appearance → all panes render correctly.
20. **Offline AI assist**: with no API key in Keychain and network off,
    the app is fully usable and no errors appear.
