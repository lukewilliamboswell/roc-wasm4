# Roc nightly maintenance

Compiler upgrades are maintainer-reviewed pull requests. Install the selected exact official nightly and run the source checks with its path:

```sh
ROC=/path/to/roc ./ci/all_tests.sh
```

Use the Zig version selected by the workflows. Source and bundle lanes test temporary application copies; the published lane requires immutable released platform URLs. Keep the release workflow's existing admission checks until their reviewed replacement is ready.

A successful cart build alone does not establish a runtime compatibility verdict.
