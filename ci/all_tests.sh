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

EXAMPLES_DIR='./examples/'
PLATFORM_DIR='./platform/'
BUILD_DIR="${BUILD_DIR:-.zig-cache/roc-wasm4-ci}"
ROC_CACHE_DIR="${ROC_CACHE_DIR:-$PWD/$BUILD_DIR/roc-cache}"
SKIP_ZIG_BUILD="${SKIP_ZIG_BUILD:-0}"

mkdir -p "$BUILD_DIR"
mkdir -p "$ROC_CACHE_DIR"
export ROC_CACHE_DIR

# Roc's wasm linker path invokes `wasm-ld` directly. Zig ships it as
# `zig wasm-ld`, so put our small wrapper on PATH for local runs and CI.
export PATH="$PWD/scripts:$PATH"

echo "Roc: $("$ROC_BIN" version)"
echo "Zig: $(zig version)"

# host object
if [ "$SKIP_ZIG_BUILD" = "1" ]; then
    echo "Skipping zig build because SKIP_ZIG_BUILD=1"
else
    zig build
fi

# zig tests
if [ "$SKIP_ZIG_BUILD" = "1" ]; then
    echo "Skipping zig build test because SKIP_ZIG_BUILD=1"
else
    zig build test
fi

# roc check
for roc_file in "$EXAMPLES_DIR"*.roc; do
    "$ROC_BIN" check "$roc_file"
done

for roc_file in "$PLATFORM_DIR"*.roc; do
    "$ROC_BIN" check "$roc_file"
done

# wasm cart build smoke tests
for roc_file in "$EXAMPLES_DIR"*.roc; do
    cart_name="$(basename "$roc_file" .roc).wasm"
    echo "Building $roc_file -> $BUILD_DIR/$cart_name"
    "$ROC_BIN" build "$roc_file" --target=wasm32 --output="$BUILD_DIR/$cart_name"
    test -s "$BUILD_DIR/$cart_name"
done

# test building docs website
if [ "$SKIP_ZIG_BUILD" = "1" ]; then
    echo "Skipping local docs generation because SKIP_ZIG_BUILD=1"
else
    "$ROC_BIN" docs platform/main.roc --output="$BUILD_DIR/generated-docs"
fi

# test packaging the platform archive
if [ "$SKIP_ZIG_BUILD" = "1" ]; then
    echo "Skipping local platform bundling because SKIP_ZIG_BUILD=1"
else
    ROC="$ROC_BIN" ./bundle.sh
fi

# roc tests
"$ROC_BIN" test platform/W4.roc
"$ROC_BIN" test platform/Sprite.roc
