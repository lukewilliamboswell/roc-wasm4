# Contributing

Install the Zig version specified in [build.zig.zon](build.zig.zon), Roc, and
WASM-4 (`w4`). The `roc` field in [platform/main.roc](platform/main.roc) declares
the development compiler. Run `roc version` to check your installation.

CI installs the latest nightly, so its compiler can be newer than your local one.

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

Dispatch **Release** on the reviewed candidate branch with a new SemVer
`release_tag`. It checks release policy, builds the platform archive, tests that
archive across the runner matrix, and publishes the tested bytes and commit.
The installed build compiler must match the platform header before publication.
Existing tags are rejected; inspect existing assets before retrying a partial
publication. PR and nightly-validation runs cannot publish.

After publishing, update example URLs through a reviewed PR and run the published
example checks against the downloads.

## Documentation

Generate local docs with:

```sh
zig build
roc docs platform/main.roc --output=.zig-cache/generated-docs
python3 -m http.server 8000 --directory .zig-cache/generated-docs
```
