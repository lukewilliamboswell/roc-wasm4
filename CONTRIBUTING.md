# Contributing

Install Zig `0.16.0` and the exact Roc compiler named in the `roc` field of
`platform/main.roc`. Run `roc version` to check your installed compiler.
Install WASM-4 (`w4`) to play carts.

CI installs the latest published new-compiler nightly through `setup-roc` and
prints `roc version`. It does not select the compiler from the headers, so a
rerun can use a newer nightly. Local checks with the header compiler and CI
checks with the latest nightly can therefore exercise different versions.

## Validation

```sh
ROC=roc ./ci/all_tests.sh
ROC=roc python3 ci/examples.py published
```

The first command builds and tests the host, checks platform modules, builds all
examples against current source in temporary application copies, runs platform
Roc tests, generates docs, and bundles the platform. The second checks and builds
committed public examples against their immutable release URLs with a fresh cache.
Neither command edits committed examples. CI names these lanes Current source
and Published examples; Release separately tests the exact proposed archive on
Linux, macOS, and Windows. Cart builds are smoke tests; play-test drawing, input,
audio and game behavior with WASM-4 before release.

To work on a game, copy its whole directory and change the platform URL in your
copy to the absolute path of `platform/main.roc`. Run `zig build` before building
the copied application. For smaller carts use `zig build -Doptimize=ReleaseSmall`
and `roc build path/to/main.roc --opt=size --output=game.wasm`, then
`w4 run game.wasm`. The host defaults to 32768 bytes of dynamic memory;
`-Dmem-size=<bytes>` changes it.

## Compiler and release policy

`main` is the development branch. Compiler pins live in root headers selected by
`.github/roc-nightly.json`. Nightly updates advance all selected compiler pins and
leave released URLs unchanged. Both compatibility lanes must pass. A source fix
may require a new platform release and a separately reviewed example URL update.
Automatic merging is disabled. See [.github/ROC_NIGHTLY.md](.github/ROC_NIGHTLY.md).

Until a usable stable compiler is adopted, releases explicitly use the shared
exact-nightly bootstrap policy on `main`. This makes no stable or LTS commitment.
Remove the bootstrap exception when adopting a stable compiler. Add a compiler
compatibility branch such as `roc-0.1.x` only when that line actually exists and
needs maintenance. Backports and forward-ports are reviewed and tested manually.

Dispatch Release on the reviewed candidate branch with a new unprefixed SemVer
`release_tag`, for example `0.8.0`. It checks compiler/release policy, builds once,
tests that archive across the runner matrix using the latest nightly, and publishes those same bytes at
the tested SHA. Publication requires the installed build compiler to match the
release-policy header pin; update the headers before publishing if necessary.
Existing tags are rejected. Never blindly rerun a partial
publication: inspect the tag and assets and preserve their identity first.
PR and `nightly_validation: true` runs cannot publish.

After publication, maintainers must prepare a reviewed follow-up updating example
URLs and README release links, test actual downloads with `ci/examples.py published`,
and provide complete starter application directories and compiler instructions.
Keep the development compiler pins intact. Follow-up PR creation and validation
are currently manual; publication does not prove those tasks completed.

Generate local docs with:

```sh
zig build
roc docs platform/main.roc --output=.zig-cache/generated-docs
python3 -m http.server 8000 --directory .zig-cache/generated-docs
```

The existing release-event Pages workflow publishes the current API site.
Versioned docs retention and explicit dispatch from token-created releases still
need a separate Pages migration; do not assume a token-created release triggers
that workflow. Preserve historical URLs when implementing that migration.
