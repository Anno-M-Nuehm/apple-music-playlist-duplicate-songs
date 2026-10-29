# User Manual — Playlist Deduplicator

Playlist Deduplicator finds and removes duplicate tracks inside your
Apple Music playlists. It never deletes files, never touches other
playlists, and never modifies your library outside the one playlist
you choose to clean.

## Quick start

1. Open Music (it must be running; the app will prompt for permission
   to control Music the first time — click OK).
2. Playlist Deduplicator scans your playlists. The middle pane lists
   only the playlists containing duplicates, each with a red badge
   showing the number of duplicate groups.
3. Click a flagged playlist. The right pane shows its duplicates,
   grouped by track, with **all but the first occurrence pre-selected
   for removal**.
4. Review the pre-selection: uncheck any occurrence you want to keep,
   or use "Select all but first" / "None" per group.
5. Click **Remove Selected**. Only the checked entries are removed
   from that one playlist. The playlist re-scans automatically;
   if it's clean, it disappears from the flagged list.

## How to export a duplicate report

1. Select a playlist with duplicates.
2. Choose **File ▸ Export Report…** (⇧⌘E).
3. Pick a format: **CSV** (for Numbers/Excel) or **Markdown**
   (for reading or pasting into notes).
4. Choose a location and save. The report contains every duplicate
   group, every occurrence with its playlist position, and which
   entries were selected for removal.

## Duplicate detection rules

Two entries are duplicates when:
- they have the same persistent track ID, or
- title + artist + album match (ignoring case) **and** the durations
  are within ±2 seconds of each other.

Because of the duration check, a live version and the studio version
of the same song are **not** treated as duplicates.

The tolerance, excluded playlist names, and other settings live in the
app bundle's `config.json`.

## The three panes

| Pane | Content |
|---|---|
| Left | All your playlists with track counts |
| Middle | Only playlists containing duplicates, with count badges |
| Right | Duplicate groups of the selected playlist, with removal checkboxes |

## AI assist (optional)

Tracks whose file location is missing or invalid can be re-identified
by an AI service. This is opt-in: it requires an API key in your
Keychain and an endpoint in `config.json`. Only the track's title,
artist, and album are ever sent, over HTTPS. Without a key or network
the feature is inactive; everything else keeps working.

## Keyboard shortcuts

- **⇧⌘E** — Export report
- **⌘?** — Help (quick start + export guide)
- **Tab / arrows / Space** — navigate and toggle checkboxes
- **Return** — Remove Selected

## Privacy

No telemetry, no analytics, no crash reporting. Nothing leaves your
Mac except the optional, anonymized AI metadata calls described above.
See the README's GDPR statement for details.
