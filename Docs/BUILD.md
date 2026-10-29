# Build & Install Manual

Assumes a Mac with Xcode 15+ (Xcode 27 in your environment) and no
prior setup. No third-party dependencies, no CocoaPods/SPM packages.

## 1. Open the project

1. Clone the repo (or unzip `PlaylistDeduplicator.zip`).
2. Double-click `PlaylistDeduplicator.xcodeproj`.
   The project uses Xcode 16+ file-system-synchronized groups, so all
   sources, assets, entitlements, and `config.json` are picked up
   automatically from disk.
3. If Xcode prompts to "re-sign" or "update to recommended settings",
   accept — the project ships with automatic signing and a placeholder
   team you must replace (next step).

## 2. Configure signing

1. Select the **PlaylistDeduplicator** target → **Signing & Capabilities**.
2. Check "Automatically manage signing".
3. Choose your team from the dropdown (a free Apple ID works for
   local runs; a paid account is needed for distribution).

### Sandbox choice (pick one)

**Option A — Developer ID / local use (simplest, recommended first):**
Disable App Sandbox (delete the App Sandbox capability). The app needs
to send Apple Events to Music, and macOS will ask you once for
permission ("Playlist Deduplicator wants to control Music") — click OK.

**Option B — App Sandbox on:**
Keep the App Sandbox capability and add the Apple Events temporary
exception entitlement, which is already included in
`PlaylistDeduplicator/PlaylistDeduplicator.entitlements`:
`com.apple.security.temporary-exception.apple-events = com.apple.Music`.
Note: Apple accepts this entitlement case-by-case on the App Store.

## 3. Build and run

1. Scheme: **PlaylistDeduplicator**, destination **My Mac**.
2. `⌘R`. The app launches and Music is queried on first window open.
3. First-run prompt: grant Apple Events permission when macOS asks.

## 4. Run the tests

1. Scheme: **PlaylistDeduplicator** (tests live in
   `PlaylistDeduplicatorTests`, hosted by the app target).
2. `⌘U`, or `Product ▸ Test`.

## 5. Optional: AI assist setup

The AI feature is off unless you add an API key to your Keychain:

```bash
security add-generic-password \
  -s "com.example.PlaylistDeduplicator.ai" \
  -a "ai-api-key" \
  -w "YOUR_API_KEY"
```

Endpoint, model, timeout, and the keychain service/account names are
configured in `PlaylistDeduplicator/config.json`. Without the key the
feature is simply inactive — everything else works.

## 6. Install

Drag `PlaylistDeduplicator.app` from the Products group (or
`~/Library/Developer/Xcode/DerivedData/.../Build/Products/Debug/`)
into `/Applications`.

## Troubleshooting

- **"Not authorized to send Apple Events"** → open System Settings ▸
  Privacy & Security ▸ Automation ▸ Playlist Deduplicator ▸ enable Music.
- **Music not found** → ensure the Music app is present and has been
  opened at least once with a library.
- **Removal reports "Playlist changed during removal"** → something
  modified the playlist between scan and removal; click the playlist
  again to rescan and retry. This is the safety check working as designed.
