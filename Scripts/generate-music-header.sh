#!/bin/bash
# Generates the ScriptingBridge header for Music (Generated/Music.h).
#
# Run once after cloning; re-run when Music's scripting dictionary changes.
#
# On recent macOS the sdef may not exist as a file; sdp can read the
# dictionary directly from the app bundle. Both paths are tried.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="$REPO_ROOT/PlaylistDeduplicator/Generated"
HEADER_PATH="$OUT_DIR/Music.h"
SDEF_PATH="$OUT_DIR/Music.sdef"

mkdir -p "$OUT_DIR"

for CANDIDATE in \
    "/System/Applications/Music.app/Contents/Resources/Music.sdef" \
    "/System/Applications/Music.app/Contents/Music.sdef" \
    "/Applications/Music.app/Contents/Resources/Music.sdef" \
    "/Applications/Music.app/Contents/Music.sdef"; do
    if [ -f "$CANDIDATE" ]; then
        echo "Found sdef: $CANDIDATE"
        echo "Generating $HEADER_PATH ..."
        sdp -fh -o "$HEADER_PATH" --basename Music "$CANDIDATE"
        echo "Done: $HEADER_PATH"
        exit 0
    fi
done

echo "No Music.sdef on disk; extracting dictionary from the running app..."
osascript -e 'tell application "Music" to launch' >/dev/null 2>&1 || true
MUSIC_PATH="$(osascript -e 'tell application "System Events" to get POSIX path of application file id "com.apple.Music"' 2>/dev/null)"
if [ -z "$MUSIC_PATH" ]; then
    MUSIC_PATH="/System/Applications/Music.app"
fi

if [ -d "$MUSIC_PATH" ]; then
    echo "Using bundle: $MUSIC_PATH"
    # sdp resolves the sdef inside the bundle automatically.
    sdp -fh -o "$HEADER_PATH" --basename Music "$MUSIC_PATH"
    echo "Done: $HEADER_PATH"
    exit 0
fi

echo "ERROR: Music.app not found." >&2
exit 1
