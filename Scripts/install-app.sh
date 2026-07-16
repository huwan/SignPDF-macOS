#!/bin/zsh

set -euo pipefail

ROOT_DIR="${0:A:h:h}"
SOURCE_APP="$ROOT_DIR/.build/app/SignPDF.app"
INSTALL_DIR="${HOME:?}/Applications"
INSTALLED_APP="$INSTALL_DIR/SignPDF.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

"$ROOT_DIR/Scripts/build-app.sh"
mkdir -p "$INSTALL_DIR"
/usr/bin/ditto "$SOURCE_APP" "$INSTALLED_APP"
/usr/bin/codesign --verify --deep --strict "$INSTALLED_APP"
"$LSREGISTER" -u "$SOURCE_APP" >/dev/null 2>&1 || true
"$LSREGISTER" -f "$INSTALLED_APP"

echo "$INSTALLED_APP"
