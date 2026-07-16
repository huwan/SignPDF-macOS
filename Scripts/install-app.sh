#!/bin/zsh

set -euo pipefail

ROOT_DIR="${0:A:h:h}"
SOURCE_APP="$ROOT_DIR/.build/app/SignPDF.app"
INSTALL_DIR="/Applications"
INSTALLED_APP="$INSTALL_DIR/SignPDF.app"
LEGACY_APP="${HOME:?}/Applications/SignPDF.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

"$ROOT_DIR/Scripts/build-app.sh"

if test -w "$INSTALL_DIR"; then
    /usr/bin/ditto "$SOURCE_APP" "$INSTALLED_APP"
elif /usr/bin/sudo -n true >/dev/null 2>&1; then
    /usr/bin/sudo -n /usr/bin/ditto "$SOURCE_APP" "$INSTALLED_APP"
else
    echo "Unable to install SignPDF in $INSTALL_DIR." >&2
    echo "Non-interactive administrator authorization (sudo -n) is unavailable; no password prompt was opened." >&2
    exit 1
fi

/usr/bin/codesign --verify --deep --strict "$INSTALLED_APP"
"$LSREGISTER" -u "$SOURCE_APP" >/dev/null 2>&1 || true

if test -d "$LEGACY_APP" && test ! -L "$LEGACY_APP"; then
    "$LSREGISTER" -u "$LEGACY_APP" >/dev/null 2>&1 || true
    /usr/bin/find "$LEGACY_APP" -depth -delete
fi

"$LSREGISTER" -f "$INSTALLED_APP"

echo "$INSTALLED_APP"
