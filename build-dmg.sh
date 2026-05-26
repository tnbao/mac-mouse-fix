#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

APP_NAME="Mac Mouse Fix"
VOLUME_NAME="Mac Mouse Fix"
PROJECT_NAME="Mouse Fix.xcodeproj"
SCHEME_NAME="App - Release"
CONFIGURATION="Release"

BUILD_DIR="$ROOT_DIR/build"
DERIVED_DATA_DIR="$BUILD_DIR/DerivedData"
PRODUCTS_DIR="$DERIVED_DATA_DIR/Build/Products/$CONFIGURATION"
APP_PATH="$PRODUCTS_DIR/$APP_NAME.app"

STAGE_DIR="$BUILD_DIR/dmg-stage"
DIST_DIR="$BUILD_DIR/dist"
TEMP_DMG="$DIST_DIR/MacMouseFix-temp.dmg"
OUTPUT_DMG="$DIST_DIR/MacMouseFix-unsigned.dmg"
BACKGROUND_SOURCE="$ROOT_DIR/dmg-background.png"
BACKGROUND_NAME="dmg-background.png"
MOUNT_DIR="/Volumes/$VOLUME_NAME"

if [[ ! -f "$BACKGROUND_SOURCE" ]]; then
  echo "Missing DMG background: $BACKGROUND_SOURCE" >&2
  exit 1
fi

echo "Building $APP_NAME..."
xcodebuild \
  -project "$PROJECT_NAME" \
  -scheme "$SCHEME_NAME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA_DIR" \
  CODE_SIGNING_ALLOWED=NO \
  build

if [[ ! -d "$APP_PATH" ]]; then
  echo "Build succeeded, but app was not found at: $APP_PATH" >&2
  exit 1
fi

echo "Preparing DMG staging folder..."
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR/.background" "$DIST_DIR"
cp -R "$APP_PATH" "$STAGE_DIR/"
cp "$BACKGROUND_SOURCE" "$STAGE_DIR/.background/$BACKGROUND_NAME"
ln -s /Applications "$STAGE_DIR/Applications"

echo "Creating temporary read-write DMG..."
rm -f "$TEMP_DMG" "$OUTPUT_DMG"
hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGE_DIR" \
  -ov \
  -fs HFS+ \
  -format UDRW \
  "$TEMP_DMG"

if [[ -d "$MOUNT_DIR" ]]; then
  hdiutil detach "$MOUNT_DIR" -quiet || true
fi

echo "Mounting and styling DMG..."
hdiutil attach "$TEMP_DMG" -readwrite -noverify -noautoopen -mountpoint "$MOUNT_DIR" -quiet

/usr/bin/SetFile -a V "$MOUNT_DIR/.background"
BACKGROUND_MOUNT_PATH="$MOUNT_DIR/.background/$BACKGROUND_NAME"

osascript <<APPLESCRIPT
tell application "Finder"
  set bgImage to POSIX file "$BACKGROUND_MOUNT_PATH" as alias

  tell disk "$VOLUME_NAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {200, 120, 1120, 497}

    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 128
    set text size of viewOptions to 16
    set background color of viewOptions to {65535, 65535, 65535}
    set background picture of viewOptions to bgImage

    set position of item "$APP_NAME.app" of container window to {235, 170}
    set position of item "Applications" of container window to {690, 170}

    update without registering applications
    delay 5
    update without registering applications
  end tell
end tell
APPLESCRIPT

sync
sleep 3
hdiutil detach "$MOUNT_DIR" -quiet

echo "Compressing final DMG..."
hdiutil convert \
  "$TEMP_DMG" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -o "$OUTPUT_DMG"

rm -f "$TEMP_DMG"

echo "Done: $OUTPUT_DMG"
