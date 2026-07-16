#!/bin/zsh

set -euo pipefail

ROOT_DIR="${0:A:h:h}"
BUILD_DIR="$ROOT_DIR/.build"
BUILT_APP="$BUILD_DIR/app/SignPDF.app"
CONTENTS_DIR="$BUILT_APP/Contents"
ICON_SOURCE="$ROOT_DIR/Resources/AppIcon.png"
ICONSET_DIR="$BUILD_DIR/AppIcon.iconset"
ICON_OUTPUT="$BUILD_DIR/AppIcon.icns"

cd "$ROOT_DIR"
swift build -c release

mkdir -p "$CONTENTS_DIR/MacOS" "$CONTENTS_DIR/Resources"
install -m 755 "$BUILD_DIR/release/SignPDF" "$CONTENTS_DIR/MacOS/SignPDF"
install -m 644 "$ROOT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"

if test -f "$ICON_SOURCE"; then
    mkdir -p "$ICONSET_DIR"
    make_icon() {
        sips -z "$1" "$1" "$ICON_SOURCE" --out "$ICONSET_DIR/$2" >/dev/null
    }
    make_icon 16 icon_16x16.png
    make_icon 32 icon_16x16@2x.png
    make_icon 32 icon_32x32.png
    make_icon 64 icon_32x32@2x.png
    make_icon 128 icon_128x128.png
    make_icon 256 icon_128x128@2x.png
    make_icon 256 icon_256x256.png
    make_icon 512 icon_256x256@2x.png
    make_icon 512 icon_512x512.png
    make_icon 1024 icon_512x512@2x.png
    iconutil -c icns "$ICONSET_DIR" -o "$ICON_OUTPUT"
    install -m 644 "$ICON_OUTPUT" "$CONTENTS_DIR/Resources/AppIcon.icns"
fi

/usr/bin/codesign --force --deep --sign - "$BUILT_APP"
/usr/bin/codesign --verify --deep --strict "$BUILT_APP"

echo "$BUILT_APP"
