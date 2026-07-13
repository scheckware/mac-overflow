#!/bin/bash
# Notarizes and staples the .app, then produces distributable, stapled ZIP + DMG.
#
# Prerequisite: the app must already be signed with a "Developer ID Application"
# identity + hardened runtime (that's what `make app` does).
#
# Credentials — two supported modes:
#   1. Local (keychain profile), the default:
#        NOTARY_PROFILE=MacOverflow   (created once via `xcrun notarytool
#        store-credentials`)
#   2. CI (App Store Connect API key), used when these are set:
#        NOTARY_KEY_ID, NOTARY_ISSUER_ID, NOTARY_KEY_PATH  (path to the .p8)
#
# Usage: scripts/notarize.sh [APP_PATH]
set -euo pipefail
APP="${1:-build/MacOverflow.app}"
[ -d "$APP" ] || { echo "error: $APP not found (run 'make app' first)"; exit 1; }

# Assemble notarytool auth args from whichever mode is configured.
AUTH=()
if [ -n "${NOTARY_KEY_ID:-}" ] && [ -n "${NOTARY_ISSUER_ID:-}" ] && [ -n "${NOTARY_KEY_PATH:-}" ]; then
    echo "Notarizing with App Store Connect API key (key id ${NOTARY_KEY_ID})"
    AUTH=(--key "${NOTARY_KEY_PATH}" --key-id "${NOTARY_KEY_ID}" --issuer "${NOTARY_ISSUER_ID}")
else
    PROFILE="${NOTARY_PROFILE:-MacOverflow}"
    echo "Notarizing with keychain profile '${PROFILE}'"
    AUTH=(--keychain-profile "${PROFILE}")
fi

# notarytool takes a zip/dmg/pkg, not a bare .app.
ZIP="build/MacOverflow-notarize.zip"
rm -f "$ZIP"
/usr/bin/ditto -c -k --keepParent "$APP" "$ZIP"

echo "Submitting to Apple notary service (this can take a few minutes)…"
xcrun notarytool submit "$ZIP" "${AUTH[@]}" --wait
rm -f "$ZIP"

echo "Stapling the ticket to the app…"
xcrun stapler staple "$APP"

echo "Verifying Gatekeeper acceptance…"
spctl -a -vvv "$APP"
xcrun stapler validate "$APP"

echo "Notarized and stapled: $APP"
