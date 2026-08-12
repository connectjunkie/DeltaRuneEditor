#!/bin/bash
#
# Builds DeltaruneEditor.app as a universal binary and assembles the bundle.
#
#     Tools/build-app.sh            # ad-hoc signed, fine for running locally
#     Tools/build-app.sh --sign     # signed with Developer ID (used by release.sh)
#
# Output: build/DeltaruneEditor.app

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_NAME="DeltaruneEditor"
DISPLAY_NAME="Deltarune Editor"
# Override with your own reverse-domain id before signing:
#   BUNDLE_ID=com.yourname.deltaruneeditor ./Tools/build-app.sh --sign
BUNDLE_ID="${BUNDLE_ID:-com.example.deltaruneeditor}"
VERSION="${VERSION:-1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
MIN_MACOS="15.0"

APP="$ROOT/build/$APP_NAME.app"
CONTENTS="$APP/Contents"

SIGN_MODE="adhoc"
[[ "${1:-}" == "--sign" ]] && SIGN_MODE="developer-id"

echo "==> Building universal binary (arm64 + x86_64)"
swift build -c release --arch arm64 --arch x86_64

# SwiftPM has moved this directory between releases, so look in both known places.
BINARY=""
for candidate in \
  "$ROOT/.build/out/Products/Release/$APP_NAME" \
  "$ROOT/.build/apple/Products/Release/$APP_NAME"
do
  [[ -f "$candidate" ]] && { BINARY="$candidate"; break; }
done
[[ -n "$BINARY" ]] || { echo "error: couldn't find the built $APP_NAME binary" >&2; exit 1; }
PRODUCTS_DIR="$(dirname "$BINARY")"

echo "==> Assembling $APP_NAME.app"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

cp "$BINARY" "$CONTENTS/MacOS/$APP_NAME"

# SwiftPM puts the library's resources in a side bundle. Bundle.module finds it via
# Bundle.main.resourceURL, so it has to land in Contents/Resources.
for bundle in "$PRODUCTS_DIR/"*.bundle; do
  [[ -e "$bundle" ]] || continue
  case "$(basename "$bundle")" in
    *Tests.bundle) continue ;;
  esac
  cp -R "$bundle" "$CONTENTS/Resources/"
done

[[ -f "$ROOT/Tools/AppIcon.icns" ]] && cp "$ROOT/Tools/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$DISPLAY_NAME</string>
    <key>CFBundleDisplayName</key><string>$DISPLAY_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>$MIN_MACOS</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHumanReadableCopyright</key><string>An unofficial DELTARUNE save editor. DELTARUNE is by Toby Fox.</string>
</dict>
</plist>
PLIST

echo "==> Signing ($SIGN_MODE)"
if [[ "$SIGN_MODE" == "developer-id" ]]; then
  IDENTITY="${SIGNING_IDENTITY:-$(security find-identity -v -p codesigning \
    | grep "Developer ID Application" | head -1 | sed -E 's/.*"(.*)"/\1/')}"

  if [[ -z "$IDENTITY" ]]; then
    echo "error: no 'Developer ID Application' certificate found." >&2
    echo "       See the 'Signing for distribution' section of README.md." >&2
    exit 1
  fi
  echo "    identity: $IDENTITY"

  # Hardened runtime and a secure timestamp are both required for notarization.
  codesign --force --deep --options runtime --timestamp \
    --sign "$IDENTITY" "$APP"
else
  # Ad-hoc is enough to launch on this machine; it will NOT pass Gatekeeper elsewhere.
  codesign --force --deep --sign - "$APP"
fi

codesign --verify --strict --verbose=2 "$APP" 2>&1 | sed 's/^/    /'

echo "==> Built $APP"
lipo -archs "$CONTENTS/MacOS/$APP_NAME" | sed 's/^/    architectures: /'
du -sh "$APP" | sed 's/^/    size: /'
