#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/Paste/Paste.xcodeproj"
SCHEME="Paste"
CONFIGURATION="Release"
BUILD_DIR="$ROOT_DIR/dist/build"
ARCHIVE_DIR="$ROOT_DIR/dist/archives"
EXPORT_DIR="$ROOT_DIR/dist/releases"
APP_NAME="Paste.app"
VERSION="${1:-1.0.0}"

rm -rf "$BUILD_DIR" "$ARCHIVE_DIR" "$EXPORT_DIR"
mkdir -p "$BUILD_DIR" "$ARCHIVE_DIR" "$EXPORT_DIR"

build_archive() {
  local arch="$1"
  local archive_path="$ARCHIVE_DIR/Paste-$arch.xcarchive"

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

  ditto -c -k --sequesterRsrc --keepParent \
    "$archive_path/Products/Applications/$APP_NAME" \
    "$EXPORT_DIR/aha-paste-$VERSION-macos-$arch.zip"
}

build_archive arm64
build_archive x86_64

echo "Release artifacts created in: $EXPORT_DIR"
