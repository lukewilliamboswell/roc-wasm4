#!/bin/bash
set -e

## Get the directory of the currently executing script
DIR="$(dirname "$0")"

# Change to that directory
cd "$DIR" || exit

# Clean up previous build
rm -rf zig-cache/
rm -rf zig-out/

zig build -Doptimize=ReleaseSmall
