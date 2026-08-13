#!/bin/bash
# Downloads the latest usagent release from GitHub and swaps it into
# /Applications in place of whatever's running there. Meant to be run by
# hand whenever you want to pick up a new release, without manually
# unzipping and dragging the app over each time.
set -euo pipefail

REPO="palamim/usagent"
APP_NAME="usagent"
INSTALLED_PATH="/Applications/$APP_NAME.app"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "Downloading latest release..."
gh release download --repo "$REPO" --pattern '*.zip' --dir "$TMP_DIR" --clobber

ZIP_PATH="$(find "$TMP_DIR" -maxdepth 1 -name '*.zip' | head -n1)"
if [ -z "$ZIP_PATH" ]; then
    echo "No release zip found." >&2
    exit 1
fi

echo "Quitting any running $APP_NAME..."
pkill -x "$APP_NAME" 2>/dev/null || true
sleep 1

echo "Unzipping..."
ditto -x -k "$ZIP_PATH" "$TMP_DIR/extracted"
NEW_APP="$TMP_DIR/extracted/$APP_NAME.app"

echo "Installing to $INSTALLED_PATH..."
if rm -rf "$INSTALLED_PATH" 2>/dev/null && cp -R "$NEW_APP" "$INSTALLED_PATH" 2>/dev/null; then
    :
else
    echo "Need admin privileges to write to /Applications..."
    osascript -e "do shell script \"rm -rf '$INSTALLED_PATH'; cp -R '$NEW_APP' '$INSTALLED_PATH'\" with administrator privileges"
fi

# The zip carries a quarantine flag from being downloaded; clear it so
# the installed copy opens normally instead of needing a right-click.
xattr -cr "$INSTALLED_PATH"

INSTALLED_VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INSTALLED_PATH/Contents/Info.plist" 2>/dev/null || echo "unknown")"

echo "Opening $APP_NAME v$INSTALLED_VERSION..."
open "$INSTALLED_PATH"

EXISTING_ITEMS="$(osascript -e 'tell application "System Events" to get the name of every login item' 2>/dev/null || echo "")"
if [[ "$EXISTING_ITEMS" != *"$APP_NAME"* ]]; then
    read -r -p "Add $APP_NAME to Login Items? [y/N] " ADD_LOGIN_ITEM
    if [[ "$ADD_LOGIN_ITEM" =~ ^[Yy]$ ]]; then
        osascript -e "tell application \"System Events\" to make login item at end with properties {path:\"$INSTALLED_PATH\", hidden:false}"
        echo "Added to Login Items."
    fi
fi

echo "Done."
