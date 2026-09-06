#!/usr/bin/env python3
"""Roc nightly PR controller. Run only from the trusted default branch.

The same controller is checked into each participating repository; repository
validation workflows are declared in .github/roc-nightly.json. No project code
is executed by this controller's privileged jobs.
"""
from __future__ import annotations

import base64
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time

BRANCH = "automation/roc-nightly"
TAG = re.compile(r"nightly-\d{4}-\d{2}-\d{2}-[0-9a-f]{7,40}")
ROOT = Path(__file__).resolve().parents[1]


def run(args, *, data=None, env=None):
    return subprocess.run(args, input=data, text=True, capture_output=True,
                          check=True, cwd=ROOT, env=env).stdout.strip()


def api(endpoint, data=None, method=None):
    args = ["gh", "api", endpoint, "-H", "X-GitHub-Api-Version: 2026-03-10"]
    if method:
        args += ["--method", method]
    if data is not None:
        args += ["--input", "-"]
    result = run(args, data=json.dumps(data) if data is not None else None)
    return json.loads(result) if result else None


def output(key, value):
    value = str(value)
    if any(c in key + value for c in "\r\n"):
        raise ValueError("Multiline workflow output")
    with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as handle:
        handle.write(f"{key}={value}\n")


def tag(value):
    if not TAG.fullmatch(value):
        raise ValueError(f"Invalid nightly tag: {value!r}")
    return value


def repo():
    value = os.environ["GITHUB_REPOSITORY"]
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", value):
        raise ValueError("Invalid repository")
    return value


def pin_at(sha):
    result = api(f"repos/{repo()}/contents/.roc-version?ref={sha}")
    return tag(base64.b64decode(result["content"]).decode().strip())


def head():
    return api(f"repos/{repo()}/git/ref/heads/{BRANCH}")["object"]["sha"]


def existing_pr():
    owner = repo().split("/")[0]
    prs = api(f"repos/{repo()}/pulls?state=open&head={owner}:{BRANCH}")
    if len(prs) > 1:
        raise ValueError("More than one nightly PR")
    return prs[0] if prs else None


def pr_body(sha, nightly, status, runs=()):
    lines = [f"Updates `.roc-version` to [{nightly}](https://github.com/roc-lang/nightlies/releases/tag/{nightly}).",
             f"Candidate commit: `{sha}`.", status]
    for item in runs:
        lines.append(f"- [{item['workflow']}]({item['html_url']}): **{item.get('conclusion') or 'pending'}**")
    lines += [f"[Updater run]({os.environ['GITHUB_SERVER_URL']}/{repo()}/actions/runs/{os.environ['GITHUB_RUN_ID']}).",
              "Created by the Roc nightly updater. Validation runs on the candidate commit. This workflow does not approve or merge PRs."]
    return "\n\n".join(lines)


def save_pr(sha, nightly, status, runs=()):
    current = existing_pr()
    data = {"title": f"Update Roc nightly to {nightly}",
            "body": pr_body(sha, nightly, status, runs)}
    if current:
        return api(f"repos/{repo()}/pulls/{current['number']}", data, "PATCH")
    data.update(head=BRANCH, base=os.environ["DEFAULT_BRANCH"])
    return api(f"repos/{repo()}/pulls", data)


def push_base(base, old):
    # Authenticate only this git invocation. Do not persist the token or pass
    # it in argv. A lease refuses to overwrite concurrent branch changes.
    env = os.environ.copy()
    auth = base64.b64encode(("x-access-token:" + env["GH_TOKEN"]).encode()).decode()
    env.update(GIT_CONFIG_COUNT="1", GIT_CONFIG_KEY_0="http.https://github.com/.extraheader",
               GIT_CONFIG_VALUE_0="AUTHORIZATION: basic " + auth)
    run(["git", "push", f"--force-with-lease=refs/heads/{BRANCH}:{old}",
         "origin", f"{base}:refs/heads/{BRANCH}"], env=env)


def signed_pin(base, nightly):
    request = {"query": """mutation($input: CreateCommitOnBranchInput!) {
      createCommitOnBranch(input: $input) { commit { oid } }
    }""", "variables": {"input": {
        "branch": {"repositoryNameWithOwner": repo(), "branchName": BRANCH},
        "expectedHeadOid": base,
        "message": {"headline": f"Update Roc nightly to {nightly}"},
        "fileChanges": {"additions": [{"path": ".roc-version",
            "contents": base64.b64encode((nightly + "\n").encode()).decode()}]},
    }}}
    sha = api("graphql", request)["data"]["createCommitOnBranch"]["commit"]["oid"]
    if not api(f"repos/{repo()}/commits/{sha}")["commit"]["verification"]["verified"]:
        raise ValueError("GitHub did not verify the update commit signature")
    return sha


def prepare():
    base = run(["git", "rev-parse", "HEAD"])
    release = api("repos/roc-lang/nightlies/releases/latest")
    nightly = tag(release["tag_name"])
    if release["draft"] or release["prerelease"] or not release["assets"]:
        raise ValueError("Latest release is not a published nightly with assets")
    if nightly == tag((ROOT / ".roc-version").read_text().strip()):
        output("changed", "false")
        return
    # An exact matching-refs lookup distinguishes absence from API failures.
    refs = api(f"repos/{repo()}/git/matching-refs/heads/{BRANCH}")
    refs = [r for r in refs if r["ref"] == f"refs/heads/{BRANCH}"]
    old = refs[0]["object"]["sha"] if refs else ""
    same = False
    if old and old != base:
        commit = api(f"repos/{repo()}/commits/{old}")
        # Never erase human work from this reserved branch.
        if len(commit["parents"]) != 1 or [f["filename"] for f in commit["files"]] != [".roc-version"]:
            raise ValueError("Nightly branch contains changes other than a pin commit")
        same = commit["parents"][0]["sha"] == base and pin_at(old) == nightly
    if same and existing_pr() and os.environ.get("FORCE", "false") != "true":
        output("changed", "false")
        return
    current = existing_pr()
    if current:
        # Clear old success before changing the branch, even if push fails.
        api(f"repos/{repo()}/pulls/{current['number']}",
            {"body": "Nightly update is being prepared. Previous validation is stale; wait for the new candidate results."}, "PATCH")
    if same:
        sha = old
    else:
        push_base(base, old)
        sha = signed_pin(base, nightly)
    save_pr(sha, nightly, "**Pending:** candidate validation has not completed.")
    for key, value in {"changed": "true", "sha": sha, "nightly": nightly, "base": base}.items():
        output(key, value)


def validate_run(item, expected_sha):
    if item["head_sha"] != expected_sha or item["head_branch"] != BRANCH or item["event"] != "workflow_dispatch":
        raise ValueError("Validation run does not belong to the candidate commit")


def validate():
    sha = os.environ["CANDIDATE_SHA"]
    workflows = json.loads((ROOT / ".github/roc-nightly.json").read_text())["workflows"]
    if not workflows or len(set(workflows)) != len(workflows):
        raise ValueError("Validation workflows must be nonempty and unique")
    runs = []
    try:
        for workflow in workflows:
            if not re.fullmatch(r"[A-Za-z0-9_-]+\.ya?ml", workflow):
                raise ValueError("Invalid workflow filename")
            if head() != sha:
                raise ValueError("Candidate branch changed before dispatch")
            dispatched = api(f"repos/{repo()}/actions/workflows/{workflow}/dispatches",
                             {"ref": BRANCH, "inputs": {"nightly_validation": True}})
            runs.append({"workflow": workflow, "id": dispatched["workflow_run_id"],
                         "html_url": dispatched["html_url"], "conclusion": None})
        deadline = time.monotonic() + 85 * 60
        while True:
            complete = True
            for item in runs:
                result = api(f"repos/{repo()}/actions/runs/{item['id']}")
                validate_run(result, sha)
                item["conclusion"] = result["conclusion"]
                complete &= result["status"] == "completed"
            output("runs", json.dumps(runs))
            if complete:
                break
            if time.monotonic() >= deadline:
                raise TimeoutError("Timed out waiting for candidate validation; see linked runs")
            time.sleep(30)
        if head() != sha:
            raise ValueError("Candidate branch changed during validation")
        if any(item["conclusion"] != "success" for item in runs):
            raise ValueError("Candidate validation did not pass")
    finally:
        output("runs", json.dumps(runs))


def report():
    sha = os.environ["CANDIDATE_SHA"]
    if head() != sha:
        raise ValueError("Refusing to report results on a different candidate")
    status = os.environ["TEST_RESULT"]
    runs = json.loads(os.environ.get("VALIDATION_RUNS") or "[]")
    expected = json.loads((ROOT / ".github/roc-nightly.json").read_text())["workflows"]
    passed = status == "success" and [r["workflow"] for r in runs] == expected and all(r["conclusion"] == "success" for r in runs)
    message = "**Passed:** all configured validation workflows passed." if passed else f"**Needs attention:** validation finished with status `{status}`. Do not merge until all validation passes."
    save_pr(sha, tag(os.environ["NIGHTLY_TAG"]), message, runs)


if __name__ == "__main__":
    commands = {"prepare": prepare, "validate": validate, "report": report}
    try:
        commands[sys.argv[1]]()
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError, TimeoutError) as error:
        # Do not print subprocess environments or authenticated git arguments.
        print(f"Nightly updater failed: {error}", file=sys.stderr)
        sys.exit(1)
