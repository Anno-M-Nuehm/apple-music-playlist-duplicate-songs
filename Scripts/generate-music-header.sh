#!/bin/bash
# Generates the ScriptingBridge header for Music (Generated/Music.h).
#
# Run once after cloning; re-run when Music's scripting dictionary changes.
#
# Strategy: use the `sdef` tool to extract the scripting dictionary from a
# Music.app bundle (sdp alone cannot open bundles on recent macOS), then
# convert it with `sdp`.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="$REPO_ROOT/PlaylistDeduplicator/Generated"
HEADER_PATH="$OUT_DIR/Music.h"
SDEF_PATH="$OUT_DIR/Music.sdef"

mkdir -p "$OUT_DIR"

candidates=()

add_bundle() {
    [ -d "$1" ] && candidates+=("$1")
}

# 1. Known install locations.
for BUNDLE in \
    "/Applications/Music.app" \
    "/System/Applications/Music.app" \
    "$HOME/Applications/Music.app"; do
    add_bundle "$BUNDLE"
done

# 2. Spotlight.
while IFS= read -r found; do
    case "$found" in
        *.app) add_bundle "$found" ;;
    esac
done < <(mdfind "kMDItemCFBundleIdentifier == 'com.apple.Music'" 2>/dev/null | sort -u)

# 3. Running Music process.
for pid in $(pgrep -x Music 2>/dev/null || true); do
    exe_path="$(ps -o comm= -p "$pid" 2>/dev/null || true)"
    case "$exe_path" in
        *.app/*)
            bundle="$(echo "$exe_path" | sed 's|\(.*\.app\)/.*|\1|')"
            add_bundle "$bundle"
            ;;
    esac
done

if [ "${#candidates[@]}" -eq 0 ]; then
    echo "ERROR: no Music.app found." >&2
    exit 1
fi

for BUNDLE in "${candidates[@]}"; do
    echo "Extracting scripting dictionary from: $BUNDLE"
    if sdef -o "$SDEF_PATH" "$BUNDLE" 2>&1; then
        if [ -s "$SDEF_PATH" ]; then
            echo "Converting to header: $HEADER_PATH"
            if sdp -fh -o "$HEADER_PATH" --basename Music "$SDEF_PATH" 2>&1; then
                if [ -s "$HEADER_PATH" ]; then
                    echo "OK: wrote $HEADER_PATH"
                    exit 0
                fi
            fi
        fi
    fi
    echo "  (failed, trying next candidate)"
done

echo "ERROR: could not generate $HEADER_PATH from any Music.app." >&2
echo "Locate Music.app on this Mac, then run:" >&2
echo "  sdef -o '$SDEF_PATH' /path/to/Music.app" >&2
echo "  sdp -fh -o '$HEADER_PATH' --basename Music '$SDEF_PATH'" >&2
exit 1
