"""Leave shaping data and serialization to WP-107's canonical writer."""

import importlib.util
import subprocess
import sys
from pathlib import Path


def generate(out: Path) -> None:
    if importlib.util.find_spec("fpengine.shaping") is None:
        print("skipped shaping (fpengine.shaping not present)")
        return
    path = out / "shaping/ot_alternatives.json"
    previous = path.read_bytes() if path.is_file() else None
    subprocess.run(
        [sys.executable, "-m", "fpengine.shaping", "write-fixture", str(path)],
        check=True,
    )
    print(f"{'unchanged' if previous == path.read_bytes() else 'wrote'} {path}")
