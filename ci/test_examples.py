"""Exercise source rewrites without changing public example admission."""
import contextlib
import io
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import examples


class ExampleLaneTests(unittest.TestCase):
    def exercise_lane(self, lane, dependency):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            original = root / 'examples/basic/main.roc'
            original.parent.mkdir(parents=True)
            source = f'app [main] {{ w4: platform "{dependency}" }}\n'
            original.write_text(source)
            commands = []

            def run(argv, **_kwargs):
                app = Path(argv[2])
                commands.append((argv[1], app.read_text()))
                if argv[1] == 'build':
                    output = next(item.split('=', 1)[1] for item in argv if item.startswith('--output='))
                    Path(output).write_bytes(b'wasm')

            argv = ['examples.py', lane]
            if lane == 'bundle':
                argv += ['--bundle-url', 'http://127.0.0.1:1234/hash.tar.zst']
            with patch.object(examples, 'ROOT', root), patch('sys.argv', argv), \
                 patch.object(examples.shutil, 'which', return_value='/compiler/roc'), \
                 patch.object(examples.subprocess, 'run', side_effect=run), \
                 contextlib.redirect_stdout(io.StringIO()):
                examples.main()
            self.assertEqual(original.read_text(), source)
            self.assertEqual([command for command, _ in commands], ['check', 'build'])
            return commands

    def test_source_lane_rewrites_a_local_platform_in_a_temporary_copy(self):
        commands = self.exercise_lane('source', '../../platform/main.roc')
        self.assertIn('../../../platform/main.roc', commands[0][1])

    def test_bundle_lane_substitutes_the_exact_candidate_url(self):
        commands = self.exercise_lane('bundle', '../../platform/main.roc')
        self.assertIn('http://127.0.0.1:1234/hash.tar.zst', commands[1][1])

    def test_published_lane_still_refuses_a_local_platform(self):
        with self.assertRaisesRegex(SystemExit, 'immutable released platform URL'):
            self.exercise_lane('published', '../../platform/main.roc')
