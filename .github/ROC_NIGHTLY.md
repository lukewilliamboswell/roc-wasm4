# Roc nightly updates

The daily caller runs at 13:46 UTC. Root header pins selected in
`.github/roc-nightly.json` declare the requested compiler; `.roc-version` is removed.
All public application pins advance together with the platform pin while released
dependency URLs stay unchanged. Automatic merging is explicitly disabled.

Shared workflows and release policy are pinned to `5c1f09b7190118f43eb901eaed0110cd53029199`.
CI uses `setup-roc` with `version: nightly-new-compiler` and no `nightly-tag`,
so each job installs the latest published nightly. `roc version` reports the
actual installed compiler. Reruns may use a newer compiler than the header pins;
these checks do not prove compatibility with an exact pinned compiler. This is
an explicit departure from the guide's exact-compiler validation policy.
The shared configuration check still verifies that selected header pins agree.
Publication requires the installed compiler to match the release-policy pin;
update the headers if a newer nightly has appeared before publishing.

Tests validates Published examples from unchanged files and a fresh cache, plus
Current source using temporary application copies. Release validates the exact
candidate archive in temporary copies. Nightly validation cannot publish.

## Rollout evidence and outstanding work

The September 7 run [34151407002](https://github.com/lukewilliamboswell/roc-wasm4/actions/runs/34151407002)
failed creating the update PR. On September 8, the repository API reported
`can_approve_pull_request_reviews: false`; the Actions PR creation setting was
enabled and read back as true, retaining read-only default token permissions.
GitHub combines creation and approval in this setting; the controller never
approves itself. The old controller suppressed the API error body.

The effective main-branch rules API returned an empty list. Maintain manual review;
configure required current-commit checks and branch protection before relying on
protected merges. No bot bypass or automatic merging is configured here.

After merging these workflow changes, manually dispatch the updater and verify
its signed candidate commit, both validation lanes, failure reporting, and a
subsequent no-op. This live acceptance has not yet been performed. Bot-triggered
PR workflows may still need workflow-start approval; dispatch success alone does
not establish required-check satisfaction.

Release URL follow-ups, starter downloads and play-testing remain manual.
Versioned Pages preservation and release-follow-up automation need separate work;
see CONTRIBUTING.md. No OpenSSF compliance or LTS support is claimed.

Follow the [integration guide](https://github.com/lukewilliamboswell/roc-automation/blob/5c1f09b7190118f43eb901eaed0110cd53029199/docs/integration.md)
for action allowlists, repository permissions and protected-merge verification.
