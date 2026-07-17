#!/bin/zsh

set -euo pipefail

ROOT_DIR="${0:A:h:h}"
VERSION="${1:?Usage: Scripts/generate-appcast.sh <version> <archive-directory>}"
ARCHIVE_DIR="${2:?Usage: Scripts/generate-appcast.sh <version> <archive-directory>}"
GENERATE_APPCAST="$ROOT_DIR/.build/artifacts/sparkle/Sparkle/bin/generate_appcast"
KEY_ACCOUNT="app.signpdf.SignPDF"

if ! test -x "$GENERATE_APPCAST"; then
    echo "Sparkle generate_appcast was not found. Run 'swift package resolve' first." >&2
    exit 1
fi

if ! test -d "$ARCHIVE_DIR"; then
    echo "Archive directory does not exist: $ARCHIVE_DIR" >&2
    exit 1
fi

"$GENERATE_APPCAST" \
    --account "$KEY_ACCOUNT" \
    --download-url-prefix "https://github.com/huwan/SignPDF-macOS/releases/download/v$VERSION/" \
    --link "https://github.com/huwan/SignPDF-macOS/releases/tag/v$VERSION" \
    --maximum-versions 3 \
    -o "$ROOT_DIR/appcast.xml" \
    "$ARCHIVE_DIR"

echo "$ROOT_DIR/appcast.xml"
