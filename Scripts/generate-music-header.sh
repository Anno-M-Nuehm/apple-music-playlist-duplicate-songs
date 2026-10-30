#!/bin/bash
# Generates the ScriptingBridge header for Music (Generated/Music.h).
#
# Run once after cloning; re-run when Music's scripting dictionary changes.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="$REPO_ROOT/PlaylistDeduplicator/Generated"
HEADER_PATH="$OUT_DIR/Music.h"
SDEF_PATH="$OUT_DIR/Music.sdef"

mkdir -p "$OUT_DIR"

try_sdef() {
    local src="$1"
    echo "Trying sdef: $src"
    if sdp -fh -o "$HEADER_PATH" --basename Music "$src" 2>&1; then
        if [ -s "$HEADER_PATH" ]; then
            echo "OK: wrote $HEADER_PATH"
            exit 0
        fi
    fi
    echo "  (failed)"
    return 1
}

try_bundle() {
    local bundle="$1"
    if [ -d "$bundle" ]; then
        echo "Trying bundle: $bundle"
        if sdp -fh -o "$HEADER_PATH" --basename Music "$bundle" 2>&1; then
            if [ -s "$HEADER_PATH" ]; then
                echo "OK: wrote $HEADER_PATH"
                exit 0
            fi
        fi
        echo "  (failed)"
    fi
    return 1
}

# 1. Known install locations.
for CANDIDATE in \
    "/System/Applications/Music.app" \
    "/Applications/Music.app" \
    "$HOME/Applications/Music.app"; do
    if [ -d "$CANDIDATE" ]; then
        for SDEF in "$CANDIDATE/Contents/Resources/Music.sdef" "$CANDIDATE/Contents/Music.sdef"; do
            if [ -f "$SDEF" ]; then
                try_sdef "$SDEF" || true
            fi
        done
        try_bundle "$CANDIDATE" || true
    fi
done

# 2. Locate Music via Spotlight (no permissions needed).
echo "Searching for Music.app via mdfind..."
while IFS= read -r mdfind_path; do
    [ -d "$mdfind_path" ] || continue
    case "$mdfind_path" in
        *.app) try_bundle "$mdfind_path" || true ;;
    esac
done < <(mdfind "kMDItemCFBundleIdentifier == 'com.apple.Music'" 2>/dev/null | sort -u)

# 3. Locate via running process (ls / proc fallback, no osascript needed).
echo "Checking running Music processes..."
for pid in $(pgrep -x Music 2>/dev/null || true); do
    exe_path="$(lsof -p "$pid" 2>/dev/null | awk '$4=="txt" && /Music\.app/ {print $NF; exit}')"
    if [ -n "$exe_path" ]; then
        bundle="$(echo "$exe_path" | sed 's|\(.*\.app\)/.*|\1|')"
        try_bundle "$bundle" || true
    fi
done

# 4. Last resort: copy sdef from Music's Resources via its Info.plist.
echo "ERROR: could not generate $HEADER_PATH." >&2
echo "Please locate Music.app on this Mac and run:" >&2
echo "  sdp -fh -o '$HEADER_PATH' --basename Music /path/to/Music.app" >&2
exit 1
