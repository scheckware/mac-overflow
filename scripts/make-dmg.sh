#!/bin/bash
# Builds a DMG from an existing .app bundle. Does NOT rebuild or re-sign the app,
# so it's safe to run after notarizing/stapling (the DMG then carries the stapled
# app). Usage: scripts/make-dmg.sh [APP_PATH] [OUTPUT_DMG]
set -euo pipefail
APP="${1:-build/MacOverflow.app}"
OUT="${2:-build/MacOverflow.dmg}"

[ -d "$APP" ] || { echo "error: $APP not found (run 'make app' first)"; exit 1; }
rm -f "$OUT"

if command -v create-dmg >/dev/null 2>&1; then
    create-dmg \
        --volname "Mac Overflow" \
        --window-pos 200 120 \
        --window-size 600 400 \
        --icon-size 100 \
        --icon "MacOverflow.app" 175 120 \
        --hide-extension "MacOverflow.app" \
        --app-drop-link 425 120 \
        "$OUT" "$APP" \
    || hdiutil create -volname "Mac Overflow" -srcfolder "$APP" -ov -format UDZO "$OUT"
else
    hdiutil create -volname "Mac Overflow" -srcfolder "$APP" -ov -format UDZO "$OUT"
fi

echo "DMG created at $OUT"
