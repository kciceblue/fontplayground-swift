"""A stage with no cooperative checkpoints proves signal interruption works."""

import sys
import tempfile
from pathlib import Path

import fpengine.cli
import fpengine.forge


def busy(*args, **kwargs):
    (Path(tempfile.gettempdir()) / "engine-work").write_bytes(b"partial work")
    counter = 0
    while True:
        counter += 1


fpengine.forge.prepare = busy
raise SystemExit(fpengine.cli.main(sys.argv[1:]))
