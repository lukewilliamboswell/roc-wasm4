"""Read the agreed compiler headers selected by the nightly updater."""
import json
from pathlib import Path

from compiler_pins import discover, local_sources, version

root = Path(__file__).resolve().parent.parent
config = json.loads((root / '.github/roc-nightly.json').read_text())
if (root / '.roc-version').exists():
    raise SystemExit('Remove the legacy .roc-version before using header pins')
print(version(discover(local_sources(root, config['compiler_roots']))))
