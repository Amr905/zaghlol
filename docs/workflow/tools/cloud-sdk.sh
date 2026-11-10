#!/usr/bin/env bash
# Install the toolchains used by CI into the cloud workspace once per session (needs package installs
# allowed in the Claude network settings). Then: export PATH=/home/claude/sdk/flutter/bin:/home/claude/sdk/dotnet:$PATH
set -euo pipefail
SDK=${SDK:-/home/claude/sdk}
FLUTTER_VERSION=${FLUTTER_VERSION:-$(grep -E "^  FLUTTER_VERSION:" "$(dirname "$0")/../../../.github/workflows/app-ci.yml" | grep -oE "[0-9]+\.[0-9]+\.[0-9]+")}
DOTNET_VERSION=${DOTNET_VERSION:-10.0.402}
mkdir -p "$SDK"
if [ ! -x "$SDK/dotnet/dotnet" ]; then
  curl -sSL https://dot.net/v1/dotnet-install.sh -o "$SDK/dotnet-install.sh"
  bash "$SDK/dotnet-install.sh" --version "$DOTNET_VERSION" --install-dir "$SDK/dotnet"
fi
if [ ! -x "$SDK/flutter/bin/flutter" ]; then
  git clone -q --depth 1 --branch "$FLUTTER_VERSION" https://github.com/flutter/flutter.git "$SDK/flutter"
fi
"$SDK/flutter/bin/flutter" config --no-analytics >/dev/null
"$SDK/flutter/bin/flutter" --version | head -1
"$SDK/dotnet/dotnet" --version
