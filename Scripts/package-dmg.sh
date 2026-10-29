#!/usr/bin/env bash
# Builds StudyManagerFC, wraps it in an app bundle and packs that into a
# drag-to-Applications disk image ready to hand to someone else.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="StudyManagerFC"
VOLUME_NAME="Study Manager FC"
APP="$ROOT/dist/$APP_NAME.app"
DMG="$ROOT/dist/$APP_NAME.dmg"

"$ROOT/Scripts/package-app.sh"

# The mounted image shows the app beside a shortcut to Applications, so the
# whole install is a drag.
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -rf "$STAGE/$APP_NAME.app/Contents/Resources/.DS_Store"

rm -f "$DMG"
diskutil image create from "$STAGE" "$DMG" \
    --format UDZO \
    --volumeName "$VOLUME_NAME" >/dev/null

hdiutil verify "$DMG" >/dev/null

codesign --verify --strict "$APP"

echo "Packaged $DMG ($(du -h "$DMG" | cut -f1))"
