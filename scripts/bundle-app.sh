#!/bin/bash
set -euo pipefail

# Build Parallax.app bundle
# Usage: ./scripts/bundle-app.sh [--release]

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$REPO_ROOT/build"
APP_BUNDLE="$BUILD_DIR/Parallax.app"
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
ARCH="$(uname -m)"

RELEASE=false
OPT_FLAG="-Onone"
if [[ "${1:-}" == "--release" ]]; then
    RELEASE=true
    OPT_FLAG="-O"
fi

mkdir -p "$BUILD_DIR"

echo "==> Building daemon..."
if $RELEASE; then
    cargo build --release --manifest-path "$REPO_ROOT/daemon/Cargo.toml"
    DAEMON_BIN="$REPO_ROOT/target/release/parallax-daemon"
else
    cargo build --manifest-path "$REPO_ROOT/daemon/Cargo.toml"
    DAEMON_BIN="$REPO_ROOT/target/debug/parallax-daemon"
fi

echo "==> Building SwiftUI app..."
SWIFT_SOURCES=$(find "$REPO_ROOT/app/Parallax" -name '*.swift' \
    -not -name 'Package.swift' \
    -not -path '*/.build/*')

swiftc \
    $OPT_FLAG \
    -o "$BUILD_DIR/Parallax" \
    -target "${ARCH}-apple-macosx14.0" \
    -sdk "$SDK_PATH" \
    -framework SwiftUI \
    -framework AppKit \
    -parse-as-library \
    $SWIFT_SOURCES

echo "==> Creating app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy binaries
cp "$BUILD_DIR/Parallax" "$APP_BUNDLE/Contents/MacOS/Parallax"
cp "$DAEMON_BIN" "$APP_BUNDLE/Contents/MacOS/parallax-daemon"
chmod +x "$APP_BUNDLE/Contents/MacOS/Parallax"
chmod +x "$APP_BUNDLE/Contents/MacOS/parallax-daemon"

# Info.plist — NSPrincipalClass is required for macOS GUI apps
cat > "$APP_BUNDLE/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Parallax</string>
    <key>CFBundleDisplayName</key>
    <string>Parallax</string>
    <key>CFBundleIdentifier</key>
    <string>com.parallax.app</string>
    <key>CFBundleVersion</key>
    <string>0.1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>Parallax</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.developer-tools</string>
</dict>
</plist>
PLIST

# PkgInfo
printf 'APPL????' > "$APP_BUNDLE/Contents/PkgInfo"

echo "==> Parallax.app created at $APP_BUNDLE"
echo "    Run with: open $APP_BUNDLE"
