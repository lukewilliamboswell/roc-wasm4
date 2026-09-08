#!/usr/bin/env bash

set -euo pipefail

if [ -z "${ROC:-}" ]; then
  echo "ERROR: The ROC environment variable is not set.
    Set it to something like:
        ROC=roc ./ci/all_tests.sh
        or
        ROC=/path/to/roc ./ci/all_tests.sh" >&2

  exit 1
fi

case "$ROC" in
  */*) ROC_BIN="$ROC" ;;
  *) ROC_BIN="$(type -P "$ROC" || true)" ;;
esac

if [ -z "$ROC_BIN" ] || [ ! -x "$ROC_BIN" ]; then
  echo "ERROR: Could not find Roc executable: $ROC" >&2
  exit 1
fi

PLATFORM_DIR='./platform/'
BUILD_DIR="${BUILD_DIR:-.zig-cache/roc-wasm4-ci}"
ROC_CACHE_DIR="${ROC_CACHE_DIR:-$PWD/$BUILD_DIR/roc-cache}"

mkdir -p "$BUILD_DIR"
mkdir -p "$ROC_CACHE_DIR"
export ROC_CACHE_DIR

echo "Roc: $("$ROC_BIN" version)"
echo "Zig: $(zig version)"

# Build and test the current host. Archive validation uses ci/examples.py bundle.
zig build -Doptimize=ReleaseSmall
zig build test

# Current-source examples are temporary copies; committed release URLs stay intact.
ROC="$ROC_BIN" python3 ci/examples.py source

for roc_file in "$PLATFORM_DIR"*.roc; do
    "$ROC_BIN" check "$roc_file"
done

# Validate documentation and platform packaging.
"$ROC_BIN" docs platform/main.roc --output="$BUILD_DIR/generated-docs"
ROC="$ROC_BIN" ./bundle.sh

# roc tests
"$ROC_BIN" test platform/W4.roc
"$ROC_BIN" test platform/Sprite.roc
