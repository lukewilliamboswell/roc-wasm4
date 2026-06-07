#!/usr/bin/env bash

# https://vaneyckt.io/posts/safer_bash_scripts_with_set_euxo_pipefail/
set -euxo pipefail

if [ -z "${ROC:-}" ]; then
  echo "ERROR: The ROC environment variable is not set.
    Set it to something like:
        /home/username/Downloads/roc_nightly-linux_x86_64-2023-10-30-cb00cfb/roc
        or
        /home/username/gitrepos/roc/target/build/release/roc" >&2

  exit 1
fi

EXAMPLES_DIR='./examples/'
PLATFORM_DIR='./platform/'
BUILD_DIR="${BUILD_DIR:-${TMPDIR:-/tmp}/roc-wasm4-build}"

mkdir -p "$BUILD_DIR"

# host library
zig build

# roc check
for roc_file in "$EXAMPLES_DIR"*.roc; do
    "$ROC" check "$roc_file"
done

for roc_file in "$PLATFORM_DIR"*.roc; do
    "$ROC" check "$roc_file"
done

# roc tests
"$ROC" test platform/W4.roc
"$ROC" test platform/Sprite.roc

# wasm cart build smoke test
#
# Full roc build support for this WASM-4 platform is tracked upstream in:
# https://github.com/roc-lang/roc/issues/9538
"$ROC" build examples/basic.roc --target=wasm32 --output="$BUILD_DIR/basic.wasm"

# test building docs website
"$ROC" docs platform/main.roc

# test packaging the platform archive
ROC="$ROC" ./bundle.sh
