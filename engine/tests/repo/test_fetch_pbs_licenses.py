"""WP-602: the maintainer licence refresh never caches an archive that fails its checksum."""

import hashlib
import io
import os
import shutil
import subprocess
import tarfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
LICENCES = ["openssl-3", "sqlite", "mpdecimal", "expat", "liblzma", "bzip2", "libffi", "libuuid"]


def _archive() -> bytes:
    """A plain tar stands in for the .tar.zst: the stub zstd passes bytes through."""
    buffer = io.BytesIO()
    with tarfile.open(fileobj=buffer, mode="w") as tar:
        for name in [*(f"python/licenses/LICENSE.{n}.txt" for n in LICENCES), "python/PYTHON.json"]:
            data = f"{name}\n".encode()
            info = tarfile.TarInfo(name)
            info.size = len(data)
            tar.addfile(info, io.BytesIO(data))
    return buffer.getvalue()


def _setup(tmp_path: Path) -> tuple[Path, str, bytes]:
    root = tmp_path / "repo"
    (root / "scripts").mkdir(parents=True)
    for name in ("fetch-pbs-licenses.sh", "python-runtime.pin"):
        shutil.copy(REPO / "scripts" / name, root / "scripts" / name)
    pin = dict(
        line.split("=", 1) for line in (root / "scripts/python-runtime.pin").read_text().splitlines() if "=" in line
    )
    asset = f"cpython-{pin['PBS_PYTHON']}+{pin['PBS_RELEASE']}-{pin['PBS_TRIPLE']}-pgo+lto-full.tar.zst"
    good = _archive()
    served = tmp_path / "served"
    served.mkdir()
    (served / "SHA256SUMS").write_text(f"{hashlib.sha256(good).hexdigest()}  {asset}\n")
    tools = tmp_path / "bin"
    tools.mkdir()
    (tools / "curl").write_text(
        '#!/bin/sh\nfor a; do case "$prev" in -o) out=$a;; esac\n'
        '  case "$a" in https://*) url=$a;; esac; prev=$a; done\n'
        f'case "$url" in *SHA256SUMS) cp "{served}/SHA256SUMS" "$out";; *) cp "{served}/archive" "$out";; esac\n'
    )
    (tools / "zstd").write_text('#!/bin/sh\ncat "$2"\n')
    for tool in tools.iterdir():
        tool.chmod(0o755)
    return root, asset, good


def _run(root: Path, tmp_path: Path) -> subprocess.CompletedProcess:
    env = {**os.environ, "PATH": f"{tmp_path / 'bin'}{os.pathsep}{os.environ['PATH']}"}
    return subprocess.run(
        ["bash", str(root / "scripts/fetch-pbs-licenses.sh")], capture_output=True, text=True, env=env, check=False
    )


def test_bad_download_is_never_cached_and_the_next_run_recovers(tmp_path: Path) -> None:
    root, asset, good = _setup(tmp_path)
    cached = root / "build/cache/pbs" / asset
    (tmp_path / "served/archive").write_bytes(good[:100])
    result = _run(root, tmp_path)
    assert result.returncode == 1 and "SHA-256 mismatch" in result.stderr
    assert not cached.exists()
    (tmp_path / "served/archive").write_bytes(good)
    result = _run(root, tmp_path)
    assert result.returncode == 0, result.stderr
    assert cached.read_bytes() == good
    assert sorted(p.name for p in (root / "App/Licenses/python-build-standalone").iterdir()) == sorted(
        f"LICENSE.{n}.txt" for n in LICENCES
    )


def test_corrupt_cached_archive_is_replaced(tmp_path: Path) -> None:
    root, asset, good = _setup(tmp_path)
    cached = root / "build/cache/pbs" / asset
    cached.parent.mkdir(parents=True)
    cached.write_bytes(b"truncated")
    (tmp_path / "served/archive").write_bytes(good)
    result = _run(root, tmp_path)
    assert result.returncode == 0, result.stderr
    assert "removing cached" in result.stderr and cached.read_bytes() == good
