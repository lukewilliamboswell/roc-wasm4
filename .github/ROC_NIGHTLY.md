# Roc nightly updates

The scheduled workflow opens compiler-update PRs for the root headers selected
in `.github/roc-nightly.json`. Released dependency URLs stay unchanged. With
`auto_merge: true`, the updater squash-merges pin-only updates after all configured
validation workflows pass and it rechecks the candidate and protected-branch rules.
Failed candidates stay open; put compatibility fixes on a separate branch.
GitHub's repository-level **Allow auto-merge** setting is not required by this
controller, which requests an immediate merge after validation.

CI uses the latest nightly installed by `setup-roc` and reports it with
`roc version`. Published examples exercise released downloads; current-source
checks use temporary application copies; release checks test the proposed archive.
Validation runs cannot publish releases.

To retry an update, run **Update Roc nightly** from the Actions tab. Inspect its
linked validation runs when diagnosing a failed candidate.
After merging a compatibility fix, manually run the updater to rebuild and
revalidate the candidate against the updated default branch. A scheduled run
skips an unchanged candidate that already has an open PR.

See the shared [integration guide](https://github.com/lukewilliamboswell/roc-automation/blob/main/docs/integration.md)
for repository permissions and workflow configuration.
