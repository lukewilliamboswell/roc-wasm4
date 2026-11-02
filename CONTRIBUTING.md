# Contributing

Install a current official Roc nightly as `roc` and [Blueprint 0.11.0](https://github.com/lukewilliamboswell/roc-blueprint/releases/tag/0.11.0).
Blueprint downloads and verifies the Zig 0.16.0 toolchain and the fixed `roc-stable`
compiler used by scripts. The platform and games use the `roc` on PATH.

## Validation

```sh
blueprint run check
blueprint run glue
blueprint run docs
```

The check runs shared compiler-pin and dependency policies, formatting, the Roc
script regressions, Zig allocator tests, platform checks and tests, all five cart
builds, API generation and bundling. The glue check downloads the installed
nightly's source, verifies the release asset's SHA-256, and compares regenerated
host bindings. It needs an authenticated `gh`. Review an ABI update with
`blueprint run glue -- --update`, then rerun the checks.

Repository examples use `../../platform/main.roc`. `blueprint run build-host`
builds the host before working on a game. In `blueprint shell`, build a cart with
`roc build examples/basic/main.roc --target=wasm32 --output=basic.wasm`, then run it
with `w4 run basic.wasm`. The host reserves 32768 bytes for dynamic allocation;
`zig build -Dmem-size=<bytes>` changes that limit.

CI checks and builds carts; it does not execute WASM-4. Play-test drawing, input,
audio and game behavior before release. The shared release-compatibility runner
currently requires a runtime command for cross targets, so it cannot report a
build-only WASM-4 suite as compatible. Remaining release-suite and runtime work
is tracked in [#73](https://github.com/lukewilliamboswell/roc-wasm4/issues/73).

## Releases

Author `docs/releases/VERSION.md`, merge the reviewed changes, and dispatch
**Release** on main with a new SemVer `release_tag` and `nightly_validation: false`.
Admission checks the default-branch commit and rejects an existing tag before
building. One nightly is selected for the entire bundle matrix. Linux, macOS
and Windows check and build the examples against the exact candidate bundle
using an empty package cache; they do not rebuild the host.

The separate shared publisher creates a draft, verifies uploaded assets against
the tested bytes and publishes it. It runs no repository tasks with write access.
Normal PR runs and the default manual validation mode cannot publish.
A validation run uses `0.0.0-ci` when no release version is supplied.

Committed examples always follow the working tree; never rewrite them after a
release. To test a bundle locally, serve its directory on loopback and run
`blueprint run examples -- --bundle-url http://127.0.0.1:8000/HASH.tar.zst`.
Python is used in CI only as that HTTP adapter.

## Documentation

Keep documentation focused on current reader tasks. Remove superseded guidance
and status narratives; keep release changes in release records and unresolved
work in issues. Follow the [shared documentation guide](https://lukewilliamboswell.github.io/roc-automation/documentation.html#write-project-documentation).

Edit `docs/index.adoc` for the manual and source documentation for the API.
`blueprint run docs` uses the locked `roc-docs` 0.9.0 utility to produce
`.docs-out/site`, the PDF and Markdown manual. The documentation workflow builds
with read-only permissions, then deploys the site in a separate job.
