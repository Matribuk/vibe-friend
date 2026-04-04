#!/bin/bash
# Notarize VibeFriend.app and staple the ticket.
# Usage: ./notarize.sh <apple-id-email> <app-specific-password>
#   App-specific password: https://appleid.apple.com → Security → App-Specific Passwords
set -e

APP_BUNDLE="VibeFriend.app"
TEAM_ID="${3:-$(security find-identity -v -p codesigning | grep "Developer ID Application" | sed 's/.*(\(.*\)).*/\1/' | head -1)}"
APPLE_ID="${1:?Usage: ./notarize.sh <apple-id> <app-specific-password>}"
APP_PASSWORD="${2:?Usage: ./notarize.sh <apple-id> <app-specific-password>}"

echo "→ Zipping $APP_BUNDLE..."
ditto -c -k --keepParent "$APP_BUNDLE" VibeFriend.zip

echo "→ Submitting to Apple notarization service..."
xcrun notarytool submit VibeFriend.zip \
    --apple-id "$APPLE_ID" \
    --team-id "$TEAM_ID" \
    --password "$APP_PASSWORD" \
    --wait

echo "→ Stapling ticket to app..."
xcrun stapler staple "$APP_BUNDLE"

rm VibeFriend.zip
echo "✓ Done — VibeFriend.app is notarized and ready to distribute."
