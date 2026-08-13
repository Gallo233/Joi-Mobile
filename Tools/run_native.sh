#!/bin/bash
# Generates, builds, installs and launches the native (Live2D + VRM) app.
#
# This exists because the spec ladder has a trap that has now cost two debugging
# cycles: `xcodebuild test` against the default `project.yml` installs an app with
# no vendor runtime over the native one on the same simulator, after which the
# character stage correctly shows the static fallback and looks broken. Running
# this script after any default-spec verification puts the native build back.
#
#   Tools/run_native.sh                     # iPhone 17 Pro
#   Tools/run_native.sh "iPhone 17e"
set -euo pipefail

DEVICE="${1:-iPhone 17 Pro}"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED="${JOI_DERIVED_PATH:-/tmp/JoiMobileNative}"
BUNDLE="com.joi.mobile"

cd "$REPO"

for vendor in Vendor/Live2D Vendor/VRMMetalKit; do
    if [ ! -d "$vendor" ]; then
        echo "error: $vendor missing. Run Tools/setup_live2d.sh and Tools/setup_vrm.sh first." >&2
        exit 1
    fi
done

echo "==> generating project.native.yml"
xcodegen generate --spec project.native.yml >/dev/null

echo "==> building for $DEVICE"
xcodebuild -project JoiMobile.xcodeproj -scheme JoiMobile \
    -destination "platform=iOS Simulator,name=$DEVICE" \
    -derivedDataPath "$DERIVED" build >/dev/null

APP="$DERIVED/Build/Products/Debug-iphonesimulator/JoiMobile.app"
if [ ! -d "$APP" ]; then
    echo "error: build produced no app at $APP" >&2
    exit 1
fi

# A build that silently lost its runtimes would look identical to a working one
# until a character failed to render, so verify rather than assume.
if [ ! -d "$APP/FrameworkMetallibs" ]; then
    echo "error: $APP has no FrameworkMetallibs; the Live2D shader phase did not run." >&2
    exit 1
fi

echo "==> installing and launching"
xcrun simctl bootstatus "$DEVICE" -b >/dev/null 2>&1 || true
xcrun simctl install "$DEVICE" "$APP"
xcrun simctl launch --terminate-running-process "$DEVICE" "$BUNDLE" >/dev/null

echo "==> running: native build with Live2D and VRM"
echo "    to place test packages where the picker can reach them:"
echo "      cp *.joi-character \"\$(xcrun simctl get_app_container '$DEVICE' $BUNDLE data)/Documents/\""
