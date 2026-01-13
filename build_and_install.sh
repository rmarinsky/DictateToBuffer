#!/bin/bash

# Build DictateToBuffer and install to /Applications

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

APP_NAME="DictateToBuffer"
BUILD_DIR="$SCRIPT_DIR/build"
APP_PATH="$BUILD_DIR/Release/${APP_NAME}.app"
INSTALL_PATH="/Applications/${APP_NAME}.app"

echo "=== Building $APP_NAME ==="
echo ""

# Check if xcodegen is installed and project needs regenerating
if [ ! -f "${APP_NAME}.xcodeproj/project.pbxproj" ]; then
    echo "Xcode project not found. Generating..."
    if ! command -v xcodegen &> /dev/null; then
        echo "XcodeGen not found. Installing via Homebrew..."
        brew install xcodegen
    fi
    xcodegen generate
    echo ""
fi

# Clean previous build
echo "Cleaning previous build..."
rm -rf "$BUILD_DIR"

# Build the app
echo "Building $APP_NAME (Release)..."
xcodebuild \
    -project "${APP_NAME}.xcodeproj" \
    -scheme "$APP_NAME" \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR" \
    CONFIGURATION_BUILD_DIR="$BUILD_DIR/Release" \
    clean build \
    | grep -E "^(Build|Compiling|Linking|error:|warning:|\*\*)" || true

# Check if build succeeded
if [ ! -d "$APP_PATH" ]; then
    echo ""
    echo "Build failed. App not found at: $APP_PATH"
    exit 1
fi

echo ""
echo "Build successful: $APP_PATH"

# Remove old installation if exists
if [ -d "$INSTALL_PATH" ]; then
    echo "Removing existing installation..."
    rm -rf "$INSTALL_PATH"
fi

# Copy to /Applications
echo "Installing to $INSTALL_PATH..."
cp -R "$APP_PATH" "$INSTALL_PATH"

echo ""
echo "=== Installation Complete ==="
echo "App installed to: $INSTALL_PATH"
echo ""
echo "To launch: open -a '$APP_NAME'"
