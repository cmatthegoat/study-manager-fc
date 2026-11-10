#!/usr/bin/env bash
# Build, verify, package and relaunch the app in one step.
#
# The self-test runs first and its failure stops the script, so a broken build never
# replaces the copy in dist/ with something worse than what is already there.
set -euo pipefail
cd "$(dirname "$0")/.."

swift run StudyManagerFC --self-test

# Quit only the packaged app, by bundle id, so nothing else on the machine is touched.
osascript -e 'tell application id "com.studymanagerfc.app" to quit' >/dev/null 2>&1 || true
sleep 2

Scripts/package-app.sh
codesign -v dist/StudyManagerFC.app
open dist/StudyManagerFC.app
echo "Running: $(pgrep -f 'dist/StudyManagerFC.app/Contents/MacOS/StudyManagerFC' | head -1)"
