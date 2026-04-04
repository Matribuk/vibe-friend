#!/bin/bash
set -e

APP_NAME="VibeFriend"
BUILD_DIR=".build/release"
APP_BUNDLE="$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS="$CONTENTS/MacOS"

# Build release binary
swift build -c release

# Clean and recreate app bundle structure
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS"

# Copy binary
cp "$BUILD_DIR/$APP_NAME" "$MACOS/$APP_NAME"

# Copy Info.plist
cp "Sources/VibeFriend/Info.plist" "$CONTENTS/Info.plist"

# Copy app icon
mkdir -p "$CONTENTS/Resources"
cp "Sources/VibeFriend/Resources/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"

# Code sign (requires Developer ID Application cert in Keychain)
if security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
    CERT=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | sed 's/.*"\(.*\)"/\1/')
    codesign --deep --force --options runtime \
        --entitlements VibeFriend.entitlements \
        --sign "$CERT" \
        "$APP_BUNDLE"
    echo "Signed: $APP_BUNDLE"
else
    echo "⚠️  No Developer ID cert found — skipping signing"
fi

echo "Built: $APP_BUNDLE"
echo "Run with: open $APP_BUNDLE"
echo "Or move to /Applications for permanent use."
