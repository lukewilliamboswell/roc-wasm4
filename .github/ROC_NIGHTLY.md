# Roc nightly updates

The scheduled workflow opens compiler-update PRs for the root headers selected
in `.github/roc-nightly.json`. Released dependency URLs stay unchanged. Review
and merge updates after validation passes.

CI uses the latest nightly installed by `setup-roc` and reports it with
`roc version`. Published examples exercise released downloads; current-source
checks use temporary application copies; release checks test the proposed archive.
Validation runs cannot publish releases.

To retry an update, run **Update Roc nightly** from the Actions tab. Inspect its
linked validation runs when diagnosing a failed candidate.

See the shared [integration guide](https://github.com/lukewilliamboswell/roc-automation/blob/main/docs/integration.md)
for repository permissions and workflow configuration.
