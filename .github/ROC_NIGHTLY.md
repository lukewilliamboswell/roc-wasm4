# Roc nightly maintenance

Use a current official nightly as `roc` on PATH. Run `blueprint run check`,
`blueprint run glue` and `blueprint run docs` before submitting an upgrade.
The fixed `roc-stable` compiler runs automation only; its version lives in
`Blueprint.roc` and script headers, independently of the product compiler.

Regenerate changed ABI bindings with `blueprint run glue -- --update` and review
the diff before rebuilding the host. A successful cart build does not establish
runtime compatibility; play-test with WASM-4 before release.
