#!/usr/bin/env bash
# Builds StudyManagerFC and wraps it in a double-clickable macOS app bundle.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="StudyManagerFC"
BUNDLE="$ROOT/dist/$APP_NAME.app"

cd "$ROOT"

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
BIN="$BIN_DIR/$APP_NAME"

if [[ ! -x "$BIN" ]]; then
    echo "error: could not find release binary at $BIN" >&2
    exit 1
fi

rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"

cp "$BIN" "$BUNDLE/Contents/MacOS/$APP_NAME"

# SwiftPM keeps bundled resources in a .bundle next to the binary; the app needs it in
# Contents/Resources for Bundle.module to find fc-database.json.
shopt -s nullglob
for resource_bundle in "$BIN_DIR"/*.bundle; do
    cp -R "$resource_bundle" "$BUNDLE/Contents/Resources/"
done
shopt -u nullglob
cp "$ROOT/Sources/StudyManagerFC/Resources/fc-database.json" "$BUNDLE/Contents/Resources/"
printf 'APPL????' > "$BUNDLE/Contents/PkgInfo"

cat > "$BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>StudyManagerFC</string>
    <key>CFBundleIdentifier</key>
    <string>com.studymanagerfc.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>StudyManagerFC</string>
    <key>CFBundleDisplayName</key>
    <string>Study Manager FC</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.sports-games</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

/usr/bin/codesign --force --sign - --timestamp=none "$BUNDLE" >/dev/null

echo "Packaged $BUNDLE"
