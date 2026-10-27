#!/usr/bin/env bash
# Builds, tests and packages the Windows desktop build as a portable zip.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT/WindowsApp/src/StudyManagerFC.Desktop/StudyManagerFC.Desktop.csproj"
TESTS="$ROOT/WindowsApp/tests/StudyManagerFC.Tests/StudyManagerFC.Tests.csproj"
OUTPUT="$ROOT/dist/StudyManagerFC-Windows"
ZIP="$ROOT/dist/StudyManagerFC-Windows-x64.zip"

if [[ -n "${DOTNET:-}" ]]; then
    DOTNET_BIN="$DOTNET"
elif command -v dotnet >/dev/null 2>&1; then
    DOTNET_BIN="dotnet"
elif [[ -x "$ROOT/.tools/dotnet/dotnet" ]]; then
    DOTNET_BIN="$ROOT/.tools/dotnet/dotnet"
else
    echo "error: no .NET SDK found. Run WindowsApp/tools/bootstrap-dotnet.sh first." >&2
    exit 1
fi

export DOTNET_CLI_TELEMETRY_OPTOUT=1
export DOTNET_NOLOGO=1

echo "==> Tests"
"$DOTNET_BIN" test "$TESTS" --nologo -v q

echo "==> Publishing win-x64"
rm -rf "$OUTPUT"
"$DOTNET_BIN" publish "$PROJECT" \
    -c Release \
    -r win-x64 \
    --self-contained true \
    -p:PublishSingleFile=true \
    -p:IncludeNativeLibrariesForSelfExtract=true \
    -p:EnableCompressionInSingleFile=true \
    -o "$OUTPUT" \
    --nologo -v q

find "$OUTPUT" -name '*.pdb' -delete

cat > "$OUTPUT/README.txt" <<'TXT'
StudyManager FC - Windows
=========================

1. Double-click StudyManagerFC.exe to play. There is nothing else to install:
   the game and the .NET runtime are bundled in that one file.

2. Windows 10 or Windows 11, 64-bit (Intel or AMD).

3. Your career saves automatically to:
       %APPDATA%\StudyManagerFC\career.json
   Copy that file to move your career between PCs, or to / from the macOS
   build (which keeps it at ~/Library/Application Support/StudyManagerFC).

4. The "Subjects" tab organises each subject into the modules you are studying.
   Add a topic, then on the Dashboard pick the subject and topic when you log a
   session and enter your marks as gained / attempted. Past papers pay 1.5x,
   exam-style questions 1.25x and homework 1x, before the subject multiplier;
   the mark percentage then scales the payout.

5. Reset everything from the "Reset" button in the top right of the game.

The game is identical to the macOS version: the same clubs, players, prices,
study rewards, Champions League format, ageing and retirement rules, and the
same save file including topics and marks.
TXT

echo "==> Zipping"
rm -f "$ZIP"
(cd "$ROOT/dist" && zip -r -q "$(basename "$ZIP")" "$(basename "$OUTPUT")")

echo "Packaged: $ZIP"
