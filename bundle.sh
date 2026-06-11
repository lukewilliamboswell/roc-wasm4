#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "$0")" && pwd)"
roc_bin="${ROC:-roc}"

# Collect all .roc files
roc_files=("$root_dir"/platform/*.roc)

# Collect the wasm32 host inputs
lib_files=()
for lib in "$root_dir"/platform/targets/wasm32/*.wasm; do
    if [[ -f "$lib" ]]; then
        lib_files+=("$lib")
    fi
done

if [[ "${#lib_files[@]}" -eq 0 ]]; then
    echo "ERROR: No wasm32 host input found. Run 'zig build' first." >&2
    exit 1
fi

echo "Bundling ${#roc_files[@]} .roc files and ${#lib_files[@]} host inputs..."

"$roc_bin" bundle "${roc_files[@]}" "${lib_files[@]}" --output-dir "$root_dir" "$@"
