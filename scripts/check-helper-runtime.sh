#!/bin/bash
# WP-203: all subprocesses are isolated and forbidden to write runtime bytecode.
set -euo pipefail
[[ $# -eq 1 ]] || { echo 'usage: check-helper-runtime.sh <runtime-dir>' >&2; exit 2; }
ROOT=$(cd "$(dirname "$0")/.." && pwd)
RT=$(cd "$1" && pwd)
SCRATCH=$(mktemp -d)
trap 'rm -rf "$SCRATCH"' EXIT
"$RT/bin/python3" -I -B - "$RT" "$ROOT" "$SCRATCH" <<'PY'
import importlib.metadata
import json
import os
import struct
import subprocess
import sys
import time
import tomllib
from pathlib import Path

runtime, repo, scratch = map(Path, sys.argv[1:])
python = runtime / 'bin/python3'
marker = time.time_ns()
current_check = 'native_m4_hello'
environment = os.environ | {'TMPDIR': str(scratch / 'tmp')}

def invoke(arguments, request=None, *, executable=python):
    result = subprocess.run([str(executable), '-I', '-B', *arguments],
                            input='' if request is None else json.dumps(request),
                            text=True, capture_output=True, env=environment)
    assert result.returncode == 0, f'exit {result.returncode}: {result.stderr[-2000:]} {result.stdout[-2000:]}'
    return result.stdout

def events(command, request=None, *, executable=python):
    return [json.loads(line) for line in invoke(['-m', 'fpengine', command], request, executable=executable).splitlines()]

def ok(name):
    print(f'check {name} OK', flush=True)

try:
    hello = events('hello')
    version = tomllib.loads((repo / 'engine/pyproject.toml').read_text())['project']['version']
    assert len(hello) == 2 and hello[0]['type'] == 'hello' and hello[0]['protocol'] == 1
    assert hello[0]['fpengine_version'] == version and hello[1]['type'] == 'result'
    ok(current_check)

    current_check = 'tooling_m2_non_editable'
    location = Path(invoke(['-c', 'import fpengine; print(fpengine.__file__)']).strip())
    assert location.is_relative_to(runtime / 'lib/python3.12/site-packages/fpengine'), location
    for pattern in ('*.pth', '__editable__*', 'direct_url.json', 'uv_cache.json'):
        assert not list(runtime.rglob(pattern)), f'found {pattern}'
    forbidden = [str(repo).encode(), str(Path.home()).encode()]
    for path in runtime.rglob('*'):
        if path.is_file() and not path.is_symlink():
            data = path.read_bytes()
            assert not any(value in data for value in forbidden), f'builder path in {path.relative_to(runtime)}'
    ok(current_check)

    current_check = 'native_m4_pipeline'
    fonts = scratch / 'fonts'
    invoke(['-m', 'fpengine.testing.make_fonts', str(fonts)])
    manifest = json.loads((fonts / 'fonts.json').read_text())
    files = [str(fonts / font['file']) for font in manifest['fonts']]
    assert len(files) == 9
    scan = events('scan', {'files': files})
    assert sum(event['type'] == 'face' for event in scan) == 9
    assert sum(event['type'] == 'file_error' for event in scan) == 1
    assert scan[-1]['type'] == 'result' and scan[-1]['command'] == 'scan'
    forged = events('forge', {
        'spec': {
            'materials': [{'path': str(fonts / name), 'index': 0} for name in
                          ('FixtureSans-Regular.ttf', 'FixtureCJK-Regular.otf')],
            'script_rules': {'han': 1, 'kana': 1, 'cjk_symbols': 1},
            'family_name': 'Fixture Runtime', 'style_name': 'Regular',
        },
        'output_path': str(scratch / 'out.ttf'),
    })
    assert forged[-1]['type'] == 'result' and forged[-1]['command'] == 'forge'
    assert forged[-1]['report']['total_codepoints'] == 3650
    assert not list((scratch / 'tmp').iterdir()), 'temporary files remain after forge'
    ok(current_check)

    current_check = 'no_bytecode_writes'
    changed = [str(p.relative_to(runtime)) for p in runtime.rglob('*')
               if p.is_file() and not p.is_symlink() and p.stat().st_mtime_ns > marker]
    assert not changed, changed
    ok(current_check)

    current_check = 'pyc_unchecked_hash'
    for source in (runtime / 'lib/python3.12').rglob('*.py'):
        bytecode = source.parent / '__pycache__' / (source.stem + '.cpython-312.pyc')
        assert bytecode.is_file(), f'missing bytecode: {source}'
        assert struct.unpack('<I', bytecode.read_bytes()[4:8])[0] == 1, f'wrong bytecode flags: {source}'
    ok(current_check)

    current_check = 'stripped'
    patterns = [
        'include', 'share', 'lib/pkgconfig', 'lib/python3.12/config-3.12-darwin', 'BUILD',
        'lib/libtcl*', 'lib/tcl*', 'lib/tk*', 'lib/itcl*', 'lib/thread*',
        'lib/python3.12/lib-dynload/_tkinter*', 'lib/python3.12/lib-dynload/_dbm*',
        'lib/python3.12/lib-dynload/_crypt*', 'lib/python3.12/turtle.py',
        'lib/python3.12/site-packages/pip', 'lib/python3.12/site-packages/pip-*.dist-info',
        'lib/python3.12/site-packages/bin',
    ] + ['lib/python3.12/' + name for name in (
        'tkinter', 'idlelib', 'turtledemo', 'ensurepip', 'lib2to3', 'pydoc_data', 'venv', '__phello__', 'test'
    )]
    for pattern in patterns:
        assert not list(runtime.glob(pattern)), f'not stripped: {pattern}'
    assert {p.name for p in (runtime / 'bin').iterdir()} == {'python3', 'python3.12'}
    assert (runtime / 'lib/python3.12/unittest').is_dir()
    ok(current_check)

    current_check = 'macho'
    binaries = [p for p in runtime.rglob('*') if p.is_file() and not p.is_symlink()
                and 'Mach-O' in subprocess.check_output(['file', '-b', str(p)], text=True)]
    assert 0 < len(binaries) <= 12, f'{len(binaries)} Mach-O files'
    for binary in binaries:
        assert subprocess.check_output(['lipo', '-archs', str(binary)], text=True).strip() == 'arm64', binary
        verified = subprocess.run(['codesign', '--verify', str(binary)], capture_output=True, text=True)
        assert verified.returncode == 0, f'{binary}: {verified.stderr}'
    ok(current_check)

    current_check = 'size'
    size = int(subprocess.check_output(['du', '-sm', str(runtime)], text=True).split()[0])
    assert size <= 85, f'{size} MB exceeds 85 MB'
    ok(current_check)

    current_check = 'relocatable'
    relocated = scratch / 'Relocated Copy/fpengine'
    subprocess.run(['ditto', str(runtime), str(relocated)], check=True)
    result = events('hello', executable=relocated / 'bin/python3')
    assert result[-1]['type'] == 'result'
    ok(current_check)

    current_check = 'licences'
    assert (runtime / 'lib/python3.12/LICENSE.txt').is_file()
    for package in ('fonttools', 'skia-pathops', 'unicodedata2'):
        distribution = importlib.metadata.distribution(package)
        assert any('.dist-info/' in str(path) and 'license' in path.name.lower()
                   and Path(distribution.locate_file(path)).is_file() for path in distribution.files), package
    ok(current_check)
except Exception as error:
    print(f'check {current_check} FAILED: {error}', file=sys.stderr, flush=True)
    sys.exit(1)
PY
