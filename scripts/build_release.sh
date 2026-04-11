#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/Paste/Paste.xcodeproj"
SCHEME="Paste"
CONFIGURATION="Release"
BUILD_DIR="$ROOT_DIR/dist/build"
ARCHIVE_DIR="$ROOT_DIR/dist/archives"
EXPORT_DIR="$ROOT_DIR/dist/releases"
DMG_DIR="$ROOT_DIR/dist/dmg"
APP_NAME="Paste.app"
VERSION="${1:-1.0.0}"

rm -rf "$BUILD_DIR" "$ARCHIVE_DIR" "$EXPORT_DIR" "$DMG_DIR"
mkdir -p "$BUILD_DIR" "$ARCHIVE_DIR" "$EXPORT_DIR" "$DMG_DIR"

sign_app() {
  local app_path="$1"

  /usr/bin/codesign \
    --force \
    --deep \
    --sign - \
    "$app_path"
}

create_dmg() {
  local arch="$1"
  local app_path="$2"
  local stage_dir="$DMG_DIR/$arch"
  local dmg_path="$EXPORT_DIR/aha-paste-$VERSION-macos-$arch.dmg"

  rm -rf "$stage_dir"
  mkdir -p "$stage_dir"
  cp -R "$app_path" "$stage_dir/$APP_NAME"
  ln -s /Applications "$stage_dir/Applications"

  hdiutil create \
    -volname "Aha Paste" \
    -srcfolder "$stage_dir" \
    -ov \
    -format UDZO \
    "$dmg_path" >/dev/null
}

build_archive() {
  local arch="$1"
  local archive_path="$ARCHIVE_DIR/Paste-$arch.xcarchive"
  local app_path="$archive_path/Products/Applications/$APP_NAME"

  xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination "generic/platform=macOS" \
    -archivePath "$archive_path" \
    -derivedDataPath "$BUILD_DIR/$arch" \
    ARCHS="$arch" \
    ONLY_ACTIVE_ARCH=NO \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    MARKETING_VERSION="$VERSION" \
    archive

  sign_app "$app_path"

  ditto -c -k --sequesterRsrc --keepParent \
    "$app_path" \
    "$EXPORT_DIR/aha-paste-$VERSION-macos-$arch.zip"

  create_dmg "$arch" "$app_path"
}

build_archive arm64
build_archive x86_64

echo "Release artifacts created in: $EXPORT_DIR"
