#!/usr/bin/env bash
# Bootstrap: install XcodeGen if missing, then generate Toggler.xcodeproj from
# project.yml. The .xcodeproj is gitignored — project.yml is the source of truth.
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v xcodegen >/dev/null 2>&1; then
  if ! command -v brew >/dev/null 2>&1; then
    echo "error: Homebrew is required to install XcodeGen automatically." >&2
    echo "       Install Homebrew (https://brew.sh) or XcodeGen manually:" >&2
    echo "         https://github.com/yonaskolb/XcodeGen#installing" >&2
    exit 1
  fi
  echo "==> Installing XcodeGen via Homebrew"
  brew install xcodegen
fi

echo "==> Generating Toggler.xcodeproj"
xcodegen generate

echo "Done. Open Toggler.xcodeproj or build with script/build_and_run.sh."
