#!/usr/bin/env bash
set -euo pipefail

INITIAL_MEMORY=65536
MAX_MEMORY=65536
STACK_SIZE=14752

# Largest 16-byte-aligned host heap observed to fit examples/rocci-bird.roc in
# one fixed WASM-4 page while preserving the old 14752-byte stack setting.
HOST_MEM_SIZE="${ROC_WASM4_MEM_SIZE:-39872}"

# WASM-4 owns low memory through the framebuffer:
#   registers:   0x0000..0x009f
#   framebuffer: 0x00a0..0x199f
# host.zig also uses a 32-byte stack canary at 0x19a0..0x19bf.
GLOBAL_BASE=6592

usage() {
    cat >&2 <<'EOF'
Usage: scripts/link_wasm4.sh <app.roc> <output.wasm>

Build a WASM-4 cartridge by compiling the Roc app to a wasm32 object and
manually linking it with platform/targets/wasm32/libhost.a.

Environment:
  ROC                    Roc compiler to use (default: roc)
  ZIG                    Zig compiler to use (default: zig)
  ROC_WASM4_MEM_SIZE     Host allocator heap size in bytes (default: 39872)
  ROC_WASM4_SKIP_ZIG_BUILD=1
                         Reuse the existing libhost.a instead of running zig build
                         The existing library must have been built with a
                         memory size that still fits the final cart.
  ROC_WASM4_KEEP_TMP=1   Keep the temporary Roc object directory
EOF
}

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

abs_path() {
    case "$1" in
        /*) printf '%s\n' "$1" ;;
        *) printf '%s/%s\n' "$PWD" "$1" ;;
    esac
}

if [[ $# -ne 2 ]]; then
    usage
    exit 2
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root_dir="$(cd "$script_dir/.." && pwd)"

app_path="$(abs_path "$1")"
output_path="$(abs_path "$2")"
output_dir="$(dirname "$output_path")"

roc_bin="${ROC:-roc}"
zig_bin="${ZIG:-zig}"
host_lib="$root_dir/platform/targets/wasm32/libhost.a"

[[ -f "$app_path" ]] || die "Roc app not found: $app_path"
mkdir -p "$output_dir"

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/wasm4-link.XXXXXXXX")"
cleanup() {
    if [[ "${ROC_WASM4_KEEP_TMP:-0}" == "1" ]]; then
        printf 'kept temp dir: %s\n' "$tmp_dir" >&2
    else
        rm -rf "$tmp_dir"
    fi
}
trap cleanup EXIT

allowed_undefined="$tmp_dir/wasm4-undefined.txt"
cat >"$allowed_undefined" <<'EOF'
blit
blitSub
diskr
diskw
hline
line
oval
rect
textUtf8
tone
traceUtf8
vline
EOF

if [[ "${ROC_WASM4_SKIP_ZIG_BUILD:-0}" != "1" ]]; then
    (cd "$root_dir" && "$zig_bin" build -Dmem-size="$HOST_MEM_SIZE")
fi
[[ -f "$host_lib" ]] || die "host library not found after zig build: $host_lib"

requested_obj="$tmp_dir/app.o"
# Current Roc no-link builds print the object path but ignore --output. Passing
# --output inside tmp_dir can remove the temp directory, so parse the printed path.
roc_output="$("$roc_bin" build "$app_path" --target=wasm32 --no-link 2>&1)" || {
    printf '%s\n' "$roc_output" >&2
    exit 1
}
printf '%s\n' "$roc_output" >&2

generated_obj="$(printf '%s\n' "$roc_output" | sed -n 's/^Object file generated: //p' | tail -n 1)"
[[ -n "$generated_obj" ]] || die "Roc did not print an object path"
[[ -f "$generated_obj" ]] || die "Roc printed an object path that does not exist: $generated_obj"
cp "$generated_obj" "$requested_obj"
app_obj="$requested_obj"

"$zig_bin" wasm-ld \
    --no-entry \
    --gc-sections \
    --import-memory \
    --initial-memory="$INITIAL_MEMORY" \
    --max-memory="$MAX_MEMORY" \
    --global-base="$GLOBAL_BASE" \
    -z "stack-size=$STACK_SIZE" \
    --export=start \
    --export=update \
    --allow-undefined-file="$allowed_undefined" \
    -o "$output_path" \
    "$app_obj" \
    "$host_lib"

if command -v wasm-tools >/dev/null 2>&1; then
    wasm-tools validate "$output_path"
fi

if command -v llvm-nm >/dev/null 2>&1; then
    undefined_symbols="$(llvm-nm --undefined-only "$output_path")"
    while read -r marker symbol; do
        [[ "$marker" == "U" ]] || continue
        case "$symbol" in
            blit | blitSub | diskr | diskw | hline | line | oval | rect | textUtf8 | tone | traceUtf8 | vline)
                ;;
            roc__*)
                die "linked wasm still has unresolved Roc symbol: $symbol"
                ;;
            *)
                die "linked wasm has unexpected unresolved symbol: $symbol"
                ;;
        esac
    done <<<"$undefined_symbols"
fi

if command -v wasm-objdump >/dev/null 2>&1; then
    dump="$(wasm-objdump -x "$output_path")"

    grep -q 'memory\[0\].*initial=1 max=1 <- env.memory' <<<"$dump" \
        || die "linked wasm does not import env.memory with one fixed 64 KiB page"
    grep -q -- '-> "start"' <<<"$dump" || die 'linked wasm does not export start'
    grep -q -- '-> "update"' <<<"$dump" || die 'linked wasm does not export update'

    stack_pointer="$(
        sed -n 's/.*<__stack_pointer> - init i32=\([0-9][0-9]*\).*/\1/p' <<<"$dump" | tail -n 1
    )"
    [[ -n "$stack_pointer" ]] || die "could not inspect __stack_pointer"

    min_data_start="$INITIAL_MEMORY"
    max_data_end=0
    while IFS= read -r line; do
        if [[ "$line" =~ memory=0[[:space:]]size=([0-9]+).*init[[:space:]]i32=([0-9]+) ]]; then
            size="${BASH_REMATCH[1]}"
            start="${BASH_REMATCH[2]}"
            end=$((start + size))
            (( start >= GLOBAL_BASE )) || die "data segment starts below safe global base: $line"
            (( start < min_data_start )) && min_data_start="$start"
            (( end > max_data_end )) && max_data_end="$end"
        fi
    done <<<"$dump"

    (( min_data_start >= GLOBAL_BASE )) || die "data starts below WASM-4 safe region"
    stack_floor=$((stack_pointer - STACK_SIZE))
    (( max_data_end <= stack_floor )) || die "static data overlaps stack"
    (( stack_pointer <= INITIAL_MEMORY )) || die "stack pointer exceeds initial memory"
fi

printf 'linked %s\n' "$output_path" >&2
