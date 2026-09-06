The Roc nightly updater checks the latest published release once a day at 13:46 UTC.
This is about four hours after roc-lang/nightlies starts its daily 09:00 UTC build.
If publication is late, the next daily check can pick it up.
It keeps `.roc-version` as the compiler pin and opens or updates one PR from
`automation/roc-nightly`. That branch is reserved for the updater; put manual
compatibility fixes on a separate branch.

The controller in `scripts/nightly_update.py` is identical across the participating
Roc packages and platforms. `.github/roc-nightly.json` declares this repository's
validation workflows:

- `tests.yaml`
- `release.yml`

Each is dispatched on the exact candidate commit with `nightly_validation: true`.
This uses GitHub API version `2026-03-10`, which returns the created workflow run ID.
The controller waits for those specific runs and checks their SHA, branch, and event
before reporting success. A failed, cancelled, skipped, timed-out or mismatched run
cannot produce a passing report. Results link to the ordinary workflow logs and
artifacts, and their jobs run on the PR head rather than the scheduled run's base SHA.

Release workflows treat this input as validation only. They build and test using the
same jobs as regular CI, while publication and deployment are excluded. Keep that
boundary when adding jobs. Every release dispatch still needs a version unless it
explicitly selects nightly validation.

The updater resets its reserved branch using an exact git lease, then creates a
GitHub-signed commit changing only `.roc-version`. It refuses to overwrite a tip
containing other file changes. It clears any old passing PR report before changing
the branch, and refuses to report results against a different head. It does not
approve PRs, enable auto-merge, merge, publish releases, or deploy sites.

Repeated schedules skip an unchanged candidate that already has an open PR. A new
nightly or new default-branch base gets a new candidate. Use Actions → Update Roc
nightly → Run workflow on the default branch to retry an unchanged candidate.
Failures in candidate tests should be diagnosed from the linked run; do not weaken
checks or replace baselines merely to accept a new compiler.

Before enabling the updater after this PR is merged:

- In Settings → Actions → General, use read-only default workflow permissions and
  enable “Allow GitHub Actions to create and approve pull requests.” The updater
  uses PR creation only; it never submits approvals. No PAT or additional secret
  is required.
- Allow the SHA-pinned actions referenced by these workflows. Grant write scopes
  only to the jobs that need branch creation, PR reporting, or workflow dispatch;
  validation jobs should use read-only contents access, apart from CodeQL's
  security-results upload permission where applicable.
- Preserve branch protection and signed-commit requirements. Require the actual
  validation job names on the candidate commit. Do not require the scheduled
  updater job, whose run belongs to the default branch. These are head-commit
  tests; use up-to-date branch requirements or a merge queue if integration with
  the latest base must also be enforced. Bots receive no bypass.
- Run the updater once after merge and confirm the signed pin commit, all selected
  validation runs, and final PR report. GitHub may also show approval-required
  automatic PR runs for GITHUB_TOKEN-created PRs; the explicitly dispatched
  validation is the unattended path. Check required-check resolution in the first
  live PR before relying on it.

The workflow exists only on this branch until merge, so its complete scheduled
and bot-token lifecycle cannot be demonstrated by the implementation PR alone.
Repository settings are not changed by this PR. The automation tests can be run
locally with `python3 -m unittest discover -s scripts/tests_nightly -v`.

Dependency pinning, least privilege and durable test evidence support OpenSSF
Best Practices adoption; this workflow alone does not establish badge compliance.
