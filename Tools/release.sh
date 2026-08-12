#!/bin/bash
#
# Builds, signs, notarizes and packages Deltarune Editor for handing to someone else.
#
#     Tools/release.sh
#
# Prerequisites, both one-off:
#   1. A "Developer ID Application" certificate in the login keychain.
#         security find-identity -v -p codesigning | grep "Developer ID Application"
#   2. Notarization credentials stored under a keychain profile:
#         xcrun notarytool store-credentials "DR_NOTARY"
#      (answer the prompts; the password is an app-specific one from appleid.apple.com)
#
# Output: build/DeltaruneEditor-<version>.dmg — notarized and stapled, so it opens on
# another Mac with no Gatekeeper warning, even with no network connection.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_NAME="DeltaruneEditor"
VOLUME_NAME="Deltarune Editor"
VERSION="${VERSION:-1.0}"
PROFILE="${NOTARY_PROFILE:-DR_NOTARY}"

APP="$ROOT/build/$APP_NAME.app"
DMG="$ROOT/build/$APP_NAME-$VERSION.dmg"
ZIP="$ROOT/build/$APP_NAME-notarize.zip"
STAGING="$ROOT/build/dmg-staging"

step() { echo; echo "==> $*"; }

# ---------------------------------------------------------------- preflight

step "Checking prerequisites"

if ! security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
  cat >&2 <<'MESSAGE'
error: no "Developer ID Application" certificate found in the keychain.

  App Store certificates cannot sign for distribution outside the store.
  Create one in Xcode: Settings > Accounts > (your team) > Manage Certificates
  > + > Developer ID Application.  Requires the Account Holder role.

  See "Signing for distribution" in README.md.
MESSAGE
  exit 1
fi
echo "    signing certificate: ok"

if ! xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
  cat >&2 <<MESSAGE
error: no notarization credentials stored under the profile "$PROFILE".

  Run this once and answer the prompts:
      xcrun notarytool store-credentials "$PROFILE"
MESSAGE
  exit 1
fi
echo "    notarization profile: ok"

# ---------------------------------------------------------------- tests

step "Running the test suite"
# A build that can't prove it reproduces real save files byte for byte must not ship.
swift test 2>&1 | tail -3

# ---------------------------------------------------------------- build

step "Building and signing the app"
VERSION="$VERSION" "$ROOT/Tools/build-app.sh" --sign

# ---------------------------------------------------------------- notarize app

step "Notarizing the app"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait
rm -f "$ZIP"

# Stapling the app itself means it launches offline, even if the dmg is discarded.
xcrun stapler staple "$APP"

# ---------------------------------------------------------------- dmg

step "Building the disk image"
rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING" \
  -ov -format UDZO \
  "$DMG" >/dev/null
rm -rf "$STAGING"

step "Notarizing the disk image"
codesign --force --timestamp \
  --sign "$(security find-identity -v -p codesigning \
    | grep "Developer ID Application" | head -1 | sed -E 's/.*"(.*)"/\1/')" \
  "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"

# ---------------------------------------------------------------- verify

step "Verifying"
echo "  app:"
spctl -a -vvv -t exec "$APP" 2>&1 | sed 's/^/    /'
xcrun stapler validate "$APP" 2>&1 | sed 's/^/    /'
echo "  disk image:"
spctl -a -vvv -t install "$DMG" 2>&1 | sed 's/^/    /'
xcrun stapler validate "$DMG" 2>&1 | sed 's/^/    /'
echo "  architectures:"
lipo -archs "$APP/Contents/MacOS/$APP_NAME" | sed 's/^/    /'

echo
echo "Done: $DMG ($(du -h "$DMG" | cut -f1))"
echo "Small enough to email. It will open on another Mac with no warning."
