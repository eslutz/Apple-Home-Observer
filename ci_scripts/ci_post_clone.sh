#!/bin/sh
set -eu

repo="${CI_PRIMARY_REPOSITORY_PATH:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$repo"

if ! command -v xcodegen >/dev/null 2>&1; then
  brew install xcodegen
fi

xcodegen generate

# Both manual workflows must pass the complete portable regression suites.
swift test
python3 -m unittest discover -s Tests -p "test_*.py"
