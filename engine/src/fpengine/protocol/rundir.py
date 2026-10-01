"""Put every engine temporary below a folder the client can sweep after SIGKILL."""

import logging
import os
import secrets
import shutil
import tempfile
from pathlib import Path

_previous: dict[Path, str | bytes | None] = {}


def open_run_dir() -> Path:
    previous = tempfile.tempdir
    base = os.environ.get("TMPDIR")
    if base:
        try:
            os.makedirs(base, exist_ok=True)
        except OSError:
            logging.getLogger(__name__).warning("Can't create TMPDIR %s; using the default temporary folder", base)
            base = None
    path = Path(tempfile.mkdtemp(prefix=f"fpengine-{os.getpid()}-", dir=base or tempfile.gettempdir()))
    _previous[path] = previous
    tempfile.tempdir = str(path)
    return path


def close_run_dir(path: Path) -> None:
    tempfile.tempdir = _previous.pop(path)
    try:
        shutil.rmtree(path)
    except FileNotFoundError:
        pass
    except OSError:
        logging.getLogger(__name__).warning("Can't remove temporary folder %s", path, exc_info=True)


def partial_path(output_path: str) -> str:
    return os.path.join(os.path.dirname(output_path), f".fpengine-{os.getpid()}-{secrets.token_hex(4)}.partial.ttf")
