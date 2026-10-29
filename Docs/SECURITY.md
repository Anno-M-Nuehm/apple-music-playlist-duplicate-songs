# Security — Threat-Model Review

Scope: the Playlist Deduplicator codebase. Rating each risk with its
mitigation as implemented.

## 1. AppleScript injection

**Risk (high if naive):** interpolating library data (playlist names,
track titles, file paths) into AppleScript source text. A playlist
named `foo" & (do shell script "rm -rf ~") & "` would execute
arbitrarily.

**Mitigation (implemented):** every script in
`AppleScriptMusicService` is a **static source string** using
positional `on run {…}` handlers. Only values passed as Apple event
*parameters* reach Music, and only the playlist ID (a validated
`UInt64`) and integer indexes (validated `Int`, range-checked in
`removeEntries`). No string from the library is ever executed or
interpolated into script text. Library data only flows back as the
script's return value, which is parsed — never executed.

**Residual risk:** none identified; the injection surface is empty by
construction. Regression safety: keep this invariant — any new script
must use parameters, never string building.

## 2. Path traversal / file-system writes

**Risk:** writing reports outside the user-chosen location, or any
modification of media files (NAS share included).

**Mitigation:** the only file writes are (a) the report, through
`NSSavePanel` — the user picks the location, the app writes exactly
that URL; (b) nothing else. The app never writes, moves, renames, or
deletes media files; the Music scripts only remove *playlist
membership entries*. `removeEntries` operates on one playlist ID and
range-checked indexes only.

## 3. MITM / network transport

**Risk:** AI-assist traffic intercepted or redirected.

**Mitigation:** the client refuses any endpoint whose scheme is not
`https`; the default endpoint is HTTPS. App Transport Security is not
weakened (no `NSAllowsArbitraryLoads` exception). Users can point
`config.json` at any provider they trust, but the scheme check is
enforced in code.

## 4. Credential handling

**Risk:** API key leaked into source, config, logs, or crash reports.

**Mitigation:** the AI key is stored only in the macOS Keychain
(`KeychainStore`), referenced by service/account names from
`config.json` — the key itself is never in code or config. It is read
at call time, used for one request header, and not persisted in
memory beyond the request. The app has no logging and no telemetry, so
no path exists for the key to reach a log. Bundle resources are
code-signed, so a tampered `config.json` fails launch verification.

## 5. Over-broad automation (blast radius)

**Risk:** a bug or a malicious script targeting more than the
selected playlist, or deleting library tracks.

**Mitigation:** all removal scripts resolve exactly
`first user playlist whose id is <id>` for the user-selected ID, and
delete only playlist *entries* at validated indexes. A before/after
track-count check inside the same script aborts the whole operation
("MISMATCH") on any unexpected state. Library-level deletion
(`delete <track>` on the library) is never issued; the scripts
contain no such construct. The integration test suite asserts other
playlists are byte-for-byte untouched.

## 6. Privacy / GDPR exposure

**Risk:** library data leaving the device.

**Mitigation:** no telemetry or analytics. The only network egress is
the opt-in AI assist, which sends title/artist/album strings only —
no user names, no library paths, no persistent IDs, no file locations.
Offline or unconfigured ⇒ no egress at all.

## 7. Untrusted config

**Risk:** a modified `config.json` enabling unwanted endpoints.

**Mitigation:** config is part of the signed app bundle; runtime
modification requires defeating code signing. Only HTTPS endpoints
are honored. The `Constants.swift` defaults are the fallback if
config is unreadable — no fail-open behavior.
