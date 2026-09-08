"""Check and build complete examples with isolated caches and temporary outputs."""
import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
RELEASE = re.compile(r'(?<=w4: platform ")https://github\.com/lukewilliamboswell/roc-wasm4/releases/download/[^/"\s]+/[A-Za-z0-9]+\.tar\.zst(?=")')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('lane', choices=['published', 'source', 'bundle'])
    parser.add_argument('--bundle-url')
    args = parser.parse_args()
    if args.lane == 'bundle' and not args.bundle_url:
        parser.error('bundle validation requires --bundle-url')
    roc = shutil.which(os.environ.get('ROC', 'roc'))
    if not roc:
        parser.error('Set ROC to an installed Roc compiler')
    examples = sorted((ROOT / 'examples').glob('*/main.roc'))
    if not examples:
        raise SystemExit('No examples found')
    scratch = ROOT / '.zig-cache'
    scratch.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='examples-', dir=scratch) as temp:
        work = Path(temp)
        env = dict(os.environ, ROC_CACHE_DIR=str(work / 'cache'))
        for example in examples:
            source = example.read_text()
            if len(RELEASE.findall(source)) != 1:
                raise SystemExit(f'{example}: expected one immutable released platform URL')
            # Public validation uses the committed file, unchanged. Other lanes
            # copy the complete application, including any companion modules.
            app = example
            if args.lane != 'published':
                app = work / example.parent.name / 'main.roc'
                shutil.copytree(example.parent, app.parent)
                dependency = ((ROOT / 'platform/main.roc').as_posix()
                              if args.lane == 'source' else args.bundle_url)
                app.write_text(RELEASE.sub(lambda _: dependency, source))
            print(f'{args.lane}: {example.relative_to(ROOT)}', flush=True)
            subprocess.run([roc, 'check', str(app)], env=env, check=True)
            output = work / f'{example.parent.name}.wasm'
            subprocess.run([roc, 'build', str(app), '--target=wasm32',
                            f'--output={output}'], env=env, check=True)
            if not output.is_file() or output.stat().st_size == 0:
                raise SystemExit(f'Missing cart: {output}')


if __name__ == '__main__':
    main()
