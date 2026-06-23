# Contributing

This document is for roc-wasm4 platform development. If you are building a game with a released platform bundle, start with the [README](README.md).

## Requirements

- [Roc](https://www.roc-lang.org/install) new-compiler nightly, available as `roc`
- [Zig](https://ziglang.org/download/) `0.16.0`
- [WASM-4 CLI](https://wasm4.org), available as `w4`, for running and bundling carts
- A Unix-like shell for `ci/all_tests.sh` and `bundle.sh`

## Source Build

Zig builds the wasm32 host object that lives at `platform/targets/wasm32/host.wasm`. Roc links that host object with an app when building a WASM-4 cart from the local platform path.

```shell
zig build
roc build examples/snake.roc
w4 run snake.wasm
```

Re-run `zig build` when changing host code or host build options such as `-Dmem-size=<bytes>`.

## Local Checks

Run the full local check suite with:

```shell
ROC=roc ./ci/all_tests.sh
```

This builds the Zig host, runs Zig tests, checks every Roc example and platform module, smoke-builds the example carts, generates docs, creates a local platform bundle, and runs platform Roc tests.

`SKIP_ZIG_BUILD=1` is reserved for release validation. It skips local host builds, docs generation, and local bundling so rewritten examples can prove they build against a downloaded platform archive.

## Local Examples

The checked-in examples use:

```roc
w4: platform "../platform/main.roc"
```

That keeps local examples pointed at source changes. After `zig build`, run an example with:

```shell
roc build examples/basic.roc
w4 run basic.wasm
```

## Documentation

Generate platform API docs locally with:

```shell
zig build
roc docs platform/main.roc --output=generated-docs
python3 -m http.server 8000 --directory generated-docs
```

Then open `http://localhost:8000`.

Docs are published by the `Generate docs` workflow when a GitHub Release is published.

## Hot Reloading

Hot reloading is useful while iterating, but it can break when state layout changes. One setup is to use [`entr`](https://github.com/eradman/entr):

```shell
find examples platform src \( -name "*.roc" -o -name "*.zig" \) \
    | entr -ccr sh -c 'zig build && roc build examples/snake.roc'
```

In another terminal:

```shell
w4 run snake.wasm --hot
```

If hot reloading stops working, press `R` in the WASM-4 runtime to reload the cart.

## Platform Bundles

Package the platform as a Roc archive with:

```shell
zig build -Doptimize=ReleaseSmall
ROC=roc ./bundle.sh
```

The bundle script writes a hash-named `.tar.zst` archive in the repository root and prints its path as `Created: ...`.

## Release Workflow

The `Release` workflow validates platform bundles before publishing:

- On pull requests, it builds a bundle and tests examples against the downloaded archive on Linux, macOS, and Windows.
- On manual dispatch with a `release_tag`, it creates a GitHub Release and attaches the generated `.tar.zst` archive.

Use the exact `.tar.zst` asset URL from the GitHub Release in downstream apps:

```roc
app [main] {
    w4: platform "https://github.com/lukewilliamboswell/roc-wasm4/releases/download/<tag>/<bundle>.tar.zst",
}
```

## Game Distribution From Source

When testing a game against a local platform checkout, build the host and Roc app with size-oriented optimizations:

```shell
zig build -Doptimize=ReleaseSmall
roc build examples/snake.roc --opt=size
```

If the cart is too large, you can try lowering the dynamic memory space with `-Dmem-size=<bytes>`. The default is `32768` bytes.
