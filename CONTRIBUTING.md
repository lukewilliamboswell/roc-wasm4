# Contributing

Install a current official Roc nightly as `roc` and [Blueprint 0.11.0](https://github.com/lukewilliamboswell/roc-blueprint/releases/tag/0.11.0).
Blueprint verifies the fixed `roc-stable` script compiler, Zig and declared tools.
The platform and games use the `roc` on PATH.

## Validate changes

```sh
blueprint run check
blueprint run glue
blueprint run docs
```

The check runs source policies, formatting, script regressions, Zig allocator
tests, platform tests and all four public games. On Linux x86_64 it runs the
games in the official WASM-4 web runtime under locked headless Chromium, then
checks optimized carts against the same recorded expectations and 64 KiB limit.
Drawing hashes, simulated input, trace output and audio/disk import calls are
checked over sixty frames. This does not test audible sound or the native runtime;
play-test those before release. `tests/spec.json` contains reviewed expectations.
Update them deliberately with `blueprint run release-test -- test-examples --update`.

The glue check verifies the installed nightly's source archive before regenerating
host bindings. It needs authenticated `gh`. Review an ABI change with
`blueprint run glue -- --update`, then rerun validation.

Repository examples use `../../platform/main.roc`. Build the host with
`blueprint run build-host`, then build and play a cart:

```sh
roc build examples/basic/main.roc --target=wasm32 --opt=size --output=basic.wasm
w4 run basic.wasm
```

The host reserves 32768 bytes for dynamic allocation. Inside `blueprint shell`,
`zig build -Dmem-size=<bytes>` changes that limit. The CI host cache fingerprints
host source, build configuration, exact locked Zig bytes and fixed build options.
A source-only check consumes that host without compiling Zig again.

## Prepare a release

Author `docs/releases/VERSION.adoc` with a `{platform-url}` placeholder and review
its rendered notes. Merge the reviewed changes, then dispatch **Release** on
`main` with `version` set to the new SemVer. Leave `version` empty for a dry run
using `0.0.1-dryrun`; an optional exact `nightly-tag` supports diagnosis.
Admission rejects an existing tag and a commit outside the current default-branch
tip. Shared release tooling validates the version against the previous bundle.

The read-only build produces a licensed platform bundle, complete examples ZIP,
versioned API ZIP, PDF manual and authored notes. Each artifact has retained
inventory, SPDX 3, SPDX 2.3, CycloneDX and binding-manifest sidecars. Reviewed
composition and explicit coverage gaps live in `sbom/`; regenerate supplier
records with `blueprint run sbom-suppliers`. A changed supplier record requires
review. OS/tool closures that are not known are recorded as incomplete.

The exact examples archive runs unchanged against the candidate bundle over
loopback with an empty package cache. Six Linux, macOS and Windows compiler-host
jobs build optimized carts; these are compilation checks, separate from Linux
browser execution. Independent verification checks transferred subject, inventory
and sidecar digests before publication. The restricted `release` job repeats that
verification, attests the exact assets, then the shared publisher uploads to a
draft, reads the assets back and publishes. PRs and empty-version runs cannot publish.

For local inspection:

```sh
blueprint run release -- prepare 0.0.1-dryrun
blueprint run release-test -- test-archive
blueprint run cross-build
blueprint run sbom-suppliers
blueprint run sbom-sidecars -- 0.0.1-dryrun
```

Committed examples always follow the working tree; never rewrite them after a
release. Nightly compatibility tests the latest published non-prerelease examples
archive, using a separate reporting job. It needs a release containing that archive.

## Documentation

Edit `docs/index.adoc` for the manual and source comments for the API.
`blueprint run docs` renders `.docs-out/site`, PDF and Markdown with locked
`roc-docs`. PRs build previews with read-only permissions. A successful final
release deploys its exact generated site from a separate job that checks out no
code. Prereleases do not replace the public site.

Keep documentation focused on current reader tasks. Put release changes in
release records and investigations in issues. Follow the
[shared documentation guide](https://lukewilliamboswell.github.io/roc-automation/documentation.html#write-project-documentation).
