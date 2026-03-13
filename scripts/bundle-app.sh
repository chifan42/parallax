#!/bin/bash
set -euo pipefail

# Build Parallax.app bundle
# Usage: ./scripts/bundle-app.sh [--release]

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$REPO_ROOT/build"
APP_BUNDLE="$BUILD_DIR/Parallax.app"

RELEASE=false
if [[ "${1:-}" == "--release" ]]; then
    RELEASE=true
fi

echo "==> Building daemon..."
if $RELEASE; then
    cargo build --release --manifest-path "$REPO_ROOT/daemon/Cargo.toml"
    DAEMON_BIN="$REPO_ROOT/target/release/parallax-daemon"
else
    cargo build --manifest-path "$REPO_ROOT/daemon/Cargo.toml"
    DAEMON_BIN="$REPO_ROOT/target/debug/parallax-daemon"
fi

echo "==> Building SwiftUI app..."
cd "$REPO_ROOT/app/Parallax"
if $RELEASE; then
    swift build -c release
    SWIFT_BIN=".build/release/Parallax"
else
    swift build
    SWIFT_BIN=".build/debug/Parallax"
fi

echo "==> Creating app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy binaries
cp "$SWIFT_BIN" "$APP_BUNDLE/Contents/MacOS/Parallax"
cp "$DAEMON_BIN" "$APP_BUNDLE/Contents/MacOS/parallax-daemon"

# Info.plist
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
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.developer-tools</string>
</dict>
</plist>
PLIST

# Entitlements for network + file access
cat > "$BUILD_DIR/Parallax.entitlements" << 'ENTITLEMENTS'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
</dict>
</plist>
ENTITLEMENTS

echo "==> Parallax.app created at $APP_BUNDLE"
echo "    Run with: open $APP_BUNDLE"
