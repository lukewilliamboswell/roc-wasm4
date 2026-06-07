#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "$0")" && pwd)"
roc_bin="${ROC:-roc}"

# Collect all .roc files
roc_files=("$root_dir"/platform/*.roc)

# Collect the wasm32 host library
lib_files=()
for lib in "$root_dir"/platform/targets/wasm32/*.a "$root_dir"/platform/targets/wasm32/*.o; do
    if [[ -f "$lib" ]]; then
        lib_files+=("$lib")
    fi
done

echo "Bundling ${#roc_files[@]} .roc files and ${#lib_files[@]} library files..."

"$roc_bin" bundle "${roc_files[@]}" "${lib_files[@]}" --output-dir "$root_dir" "$@"
