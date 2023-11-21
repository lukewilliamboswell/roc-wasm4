#!/bin/bash
set -e

## Get the directory of the currently executing script
DIR="$(dirname "$0")"

# Change to that directory
cd "$DIR" || exit

# Clean up previous build
rm -rf zig-cache/
rm -rf zig-out/
rm -rf platform/*.o
rm -rf platform/*.tar.br

roc build --target=wasm32 examples/echo.roc --opt-size --no-link
mv examples/echo.wasm examples/echo.o

# Build for wasm32
rm -rf zig-out/
zig build -Doptimize=ReleaseSmall
