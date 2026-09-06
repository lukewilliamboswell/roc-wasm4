import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

MODULE = Path(__file__).resolve().parents[1] / 'nightly_update.py'
spec = importlib.util.spec_from_file_location('nightly_update', MODULE)
n = importlib.util.module_from_spec(spec)
spec.loader.exec_module(n)

class ControllerTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        root = Path(self.tmp.name)
        (root / '.github').mkdir()
        (root / '.github/roc-nightly.json').write_text(json.dumps({'workflows': ['ci.yml', 'release.yml']}))
        (root / '.roc-version').write_text('nightly-2026-09-04-c125b82\n')
        self.env = patch.dict(os.environ, GITHUB_REPOSITORY='owner/project', GITHUB_OUTPUT=str(root/'outputs'),
                              GITHUB_SERVER_URL='https://github.com', GITHUB_RUN_ID='100', DEFAULT_BRANCH='main',
                              CANDIDATE_SHA='candidate', NIGHTLY_TAG='nightly-2026-09-05-b195f5b', GH_TOKEN='test-token')
        self.env.start(); self.addCleanup(self.env.stop)
        self.root_patch = patch.object(n, 'ROOT', root)
        self.root_patch.start(); self.addCleanup(self.root_patch.stop)

    def test_tag_rejects_injection_and_floating_versions(self):
        for value in ['nightly', 'nightly-2026-09-05-b195f5b\nother=x', 'nightly-$(whoami)', '../main']:
            with self.subTest(value=value), self.assertRaises(ValueError): n.tag(value)
        self.assertEqual(n.tag('nightly-2026-09-05-b195f5b'), 'nightly-2026-09-05-b195f5b')

    def test_outputs_reject_multiline(self):
        with self.assertRaises(ValueError): n.output('sha', 'a\nchanged=true')

    def test_signed_commit_only_changes_pin_and_checks_signature(self):
        with patch.object(n, 'api', side_effect=[{'data': {'createCommitOnBranch': {'commit': {'oid': 'signed'}}}},
                                                {'commit': {'verification': {'verified': True}}}]) as api:
            self.assertEqual(n.signed_pin('base', 'nightly-2026-09-05-b195f5b'), 'signed')
        payload = api.call_args_list[0].args[1]['variables']['input']
        self.assertEqual(payload['expectedHeadOid'], 'base')
        self.assertEqual([f['path'] for f in payload['fileChanges']['additions']], ['.roc-version'])

    def test_unverified_commit_is_rejected(self):
        with patch.object(n, 'api', side_effect=[{'data': {'createCommitOnBranch': {'commit': {'oid': 'signed'}}}},
                                                {'commit': {'verification': {'verified': False}}}]), self.assertRaises(ValueError):
            n.signed_pin('base', 'nightly-2026-09-05-b195f5b')

    def test_push_uses_exact_lease_without_token_in_arguments(self):
        with patch.object(n, 'run') as run: n.push_base('base', 'previous')
        args = run.call_args.args[0]
        self.assertIn('--force-with-lease=refs/heads/automation/roc-nightly:previous', args)
        self.assertNotIn('test-token', ' '.join(args))
        self.assertIn('GIT_CONFIG_VALUE_0', run.call_args.kwargs['env'])

    def test_prepare_noop_has_no_mutations(self):
        release = {'tag_name': 'nightly-2026-09-04-c125b82', 'draft': False, 'prerelease': False, 'assets': [{}]}
        with patch.object(n, 'run', return_value='base'), patch.object(n, 'api', return_value=release) as api:
            n.prepare()
        self.assertEqual(api.call_count, 1)
        self.assertIn('changed=false', Path(os.environ['GITHUB_OUTPUT']).read_text())

    def test_prepare_refuses_unrelated_branch_changes(self):
        release = {'tag_name': 'nightly-2026-09-05-b195f5b', 'draft': False, 'prerelease': False, 'assets': [{}]}
        refs = [{'ref': 'refs/heads/automation/roc-nightly', 'object': {'sha': 'old'}}]
        commit = {'parents': [{'sha': 'base'}], 'files': [{'filename': 'src/main.roc'}]}
        with patch.object(n, 'run', return_value='base'), patch.object(n, 'api', side_effect=[release, refs, commit]), patch.object(n, 'push_base') as push:
            with self.assertRaises(ValueError): n.prepare()
            push.assert_not_called()

    def response(self, conclusion='success', sha='candidate'):
        return {'head_sha': sha, 'head_branch': n.BRANCH, 'event': 'workflow_dispatch',
                'status': 'completed', 'conclusion': conclusion}

    def test_wrong_commit_branch_or_event_rejected(self):
        for key, value in [('head_sha', 'other'), ('head_branch', 'main'), ('event', 'push')]:
            item = self.response(); item[key] = value
            with self.subTest(key=key), self.assertRaises(ValueError): n.validate_run(item, 'candidate')

    def validate_api(self, conclusion='success'):
        def api(endpoint, data=None, method=None):
            if endpoint.endswith('/dispatches'):
                self.assertEqual(data, {'ref': n.BRANCH, 'inputs': {'nightly_validation': True}})
                return {'workflow_run_id': 7 if '/ci.yml/' in endpoint else 8, 'html_url': 'https://github.com/run'}
            self.assertIn(endpoint.rsplit('/', 1)[-1], ['7', '8'])
            return self.response(conclusion)
        return api

    def test_validate_uses_returned_ids_and_waits_for_all_workflows(self):
        with patch.object(n, 'head', return_value='candidate'), patch.object(n, 'api', side_effect=self.validate_api()) as api:
            n.validate()
        self.assertEqual(api.call_count, 4)
        self.assertIn('"id": 8', Path(os.environ['GITHUB_OUTPUT']).read_text())

    def test_failed_cancelled_or_skipped_validation_is_not_success(self):
        for status in ['failure', 'cancelled', 'skipped', 'timed_out', 'action_required']:
            with self.subTest(status=status), patch.object(n, 'head', return_value='candidate'), patch.object(n, 'api', side_effect=self.validate_api(status)), self.assertRaises(ValueError):
                n.validate()

    def test_stale_candidate_results_are_not_reported(self):
        with patch.object(n, 'head', return_value='other'), patch.object(n, 'save_pr') as save:
            with self.assertRaises(ValueError): n.report()
            save.assert_not_called()

    def test_report_requires_complete_success_evidence(self):
        for runs in [[], [{'workflow': 'ci.yml', 'conclusion': 'success'}]]:
            with patch.dict(os.environ, TEST_RESULT='success', VALIDATION_RUNS=json.dumps(runs)), patch.object(n, 'head', return_value='candidate'), patch.object(n, 'save_pr') as save:
                n.report()
                self.assertIn('Needs attention', save.call_args.args[2])

    def test_report_links_both_successful_runs(self):
        runs = [{'workflow': w, 'conclusion': 'success', 'html_url': 'https://github.com/run'} for w in ['ci.yml', 'release.yml']]
        with patch.dict(os.environ, TEST_RESULT='success', VALIDATION_RUNS=json.dumps(runs)), patch.object(n, 'head', return_value='candidate'), patch.object(n, 'save_pr') as save:
            n.report()
        self.assertIn('Passed', save.call_args.args[2])
        self.assertEqual(save.call_args.args[3], runs)

if __name__ == '__main__': unittest.main()
