#!/bin/bash
# Xcode build phase: compiles the Cubism Metal shader libraries for the platform
# being built and copies them into the app bundle's `FrameworkMetallibs`
# directory, which is where `CubismShader_Metal` looks them up by name.
#
# Metal libraries are platform-specific, so this must run per build rather than
# being vendored once. Only the three base libraries are produced here; the
# extended blend-mode variants are a separate 470-file matrix that the renderer
# loads lazily, and a model that needs one currently falls back rather than
# silently rendering the wrong blend.
set -euo pipefail

VENDOR="$SRCROOT/Vendor/Live2D"
SHADERS="$VENDOR/Framework/src/Rendering/Metal/Shaders"
OUT="$BUILT_PRODUCTS_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/FrameworkMetallibs"

if [ ! -d "$SHADERS" ]; then
    echo "error: $SHADERS missing; run Tools/setup_live2d.sh first" >&2
    exit 1
fi

case "$PLATFORM_NAME" in
    iphonesimulator) SDK_NAME=iphonesimulator ;;
    iphoneos) SDK_NAME=iphoneos ;;
    *) SDK_NAME="$PLATFORM_NAME" ;;
esac

# The only directory this phase creates is the one holding its declared
# outputs, which is what script sandboxing grants it. Nothing is written to
# $DERIVED_FILE_DIR: this is a pre-build phase, so that directory does not exist
# yet, and creating it is denied. Building into a $BUILT_PRODUCTS_DIR under /tmp
# hides that, because the sandbox allows writes anywhere under /tmp — which is
# why this only ever failed from Xcode's own DerivedData.
mkdir -p "$OUT"

for name in MetalShaders VertShaderSrcBlend VertShaderSrcMaskedBlend; do
    src="$SHADERS/$name.metal"
    lib="$OUT/$name.metallib"
    if [ ! -f "$src" ]; then
        echo "error: shader source $src missing" >&2
        exit 1
    fi
    if [ -f "$lib" ] && [ "$lib" -nt "$src" ]; then
        continue
    fi
    # Straight from .metal to .metallib. The separate .air step needed a scratch
    # directory and bought nothing: each library is one translation unit.
    xcrun -sdk "$SDK_NAME" metal -I "$SHADERS" -o "$lib" "$src"
done

echo "compiled Cubism Metal libraries for $SDK_NAME into FrameworkMetallibs"
