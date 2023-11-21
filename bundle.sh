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

# Build for wasm32
rm -rf zig-out/
zig build
 
# Run usign wasm4 runtime
w4 run zig-out/lib/wasm4.wasm