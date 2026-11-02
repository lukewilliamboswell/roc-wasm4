# Roc nightly maintenance

Compiler upgrades are maintainer-reviewed pull requests. Install the selected exact official nightly and run the source checks with its path:

```sh
ROC=/path/to/roc ./ci/all_tests.sh
```

Use the Zig version selected by the workflows. Source and bundle lanes test temporary application copies; the published lane requires immutable released platform URLs. Keep the release workflow's existing admission checks until their reviewed replacement is ready.

The retired privileged pin updater no longer runs. A successful cart build alone does not establish a runtime compatibility verdict. The executable archive and shared published-release suite migration is tracked in [#73](https://github.com/lukewilliamboswell/roc-wasm4/issues/73).
