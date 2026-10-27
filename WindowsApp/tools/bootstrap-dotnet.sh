#!/usr/bin/env bash
# Installs a local .NET 8 SDK into .tools/dotnet so the Windows build can be
# produced without touching the machine-wide installation.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TOOLS="$ROOT/.tools"
SDK_DIR="$TOOLS/dotnet"
INSTALLER="$TOOLS/dotnet-install.sh"

mkdir -p "$TOOLS"

if [[ ! -f "$INSTALLER" ]]; then
    curl -sSL --max-time 120 -o "$INSTALLER" https://dot.net/v1/dotnet-install.sh
    chmod +x "$INSTALLER"
fi

if [[ -x "$SDK_DIR/dotnet" ]]; then
    echo "Using existing SDK: $("$SDK_DIR/dotnet" --version)"
    exit 0
fi

bash "$INSTALLER" --channel 8.0 --install-dir "$SDK_DIR" --no-path
echo "Installed SDK: $("$SDK_DIR/dotnet" --version)"
