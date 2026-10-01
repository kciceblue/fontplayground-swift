#!/bin/bash
set -euo pipefail
[[ $# -ge 1 ]] || { echo 'usage: check-bundle.sh <app> [--release] [--distribution]' >&2; exit 2; }
ROOT=$(cd "$(dirname "$0")/.." && pwd)
python3 - "$ROOT" "$@" <<'PY'
import glob, json, pathlib, plistlib, re, subprocess, sys
root, app = map(pathlib.Path, sys.argv[1:3])
options = set(sys.argv[3:])
if options - {'--release', '--distribution'}:
    raise SystemExit('check-bundle: unknown option')
problems = []
def check(name, condition, detail=''):
    print('check-bundle: ' + name + (' OK' if condition else ' FAIL ' + detail))
    if not condition:
        problems.append(name)
def run(args):
    return subprocess.run([str(a) for a in args], capture_output=True)
contents = app / 'Contents'
resources = contents / 'Resources'
try:
    info = plistlib.loads((contents / 'Info.plist').read_bytes())
except (OSError, ValueError) as error:
    raise SystemExit('check-bundle: cannot read Info.plist: ' + str(error))
version = re.search(r'^MARKETING_VERSION\s*=\s*(\S+)', (root / 'App/Version.xcconfig').read_text(), re.M)[1]
copyright = next(line for line in (root / 'LICENSE').read_text().splitlines() if line.startswith('Copyright'))
expected = {
    'CFBundleIdentifier': 'io.github.kciceblue.fontplayground', 'CFBundleName': 'Font Playground',
    'CFBundleDisplayName': 'Font Playground', 'CFBundleExecutable': 'Font Playground',
    'CFBundlePackageType': 'APPL', 'CFBundleShortVersionString': version, 'LSMinimumSystemVersion': '14.0',
    'LSApplicationCategoryType': 'public.app-category.graphics-design', 'NSHumanReadableCopyright': copyright,
    'CFBundleIconName': 'AppIcon', 'CFBundleIconFile': 'AppIcon', 'CFBundleDevelopmentRegion': 'en',
    'NSHighResolutionCapable': True,
}
invalid = [key for key, value in expected.items() if info.get(key) != value]
invalid += [key for key in ['NSRequiresAquaSystemAppearance', 'UIDesignRequiresCompatibility', 'LSUIElement'] if key in info]
for name in ['DocumentsFolder', 'DesktopFolder', 'DownloadsFolder', 'RemovableVolumes', 'NetworkVolumes']:
    key = 'NS' + name + 'UsageDescription'
    if not isinstance(info.get(key), str) or not info[key].strip():
        invalid.append(key)
if not re.fullmatch(r'[1-9][0-9]*', str(info.get('CFBundleVersion', ''))):
    invalid.append('CFBundleVersion')
check('Info.plist', not invalid, ', '.join(invalid))
asset = run(['xcrun', 'assetutil', '--info', resources / 'Assets.car'])
try:
    icons = [item for item in json.loads(asset.stdout) if str(item.get('Name', '')).startswith('AppIcon')]
except (ValueError, TypeError):
    icons = []
check('icon', asset.returncode == 0 and bool(icons) and (resources / 'AppIcon.icns').is_file())
# CRIT-10 / WP-508: English and Simplified Chinese, for the app bundle and FPAppUI's resource bundle.
ui = resources / 'FontPlaygroundMacKit_FPAppUI.bundle/Contents/Resources'
required = [resources / lang / 'UserGuide.html' for lang in ['en.lproj', 'zh-Hans.lproj']]
required += [resources / 'zh-Hans.lproj/InfoPlist.strings']
required += [ui / lang / 'Localizable.strings' for lang in ['en.lproj', 'zh-Hans.lproj']]
invalid = [str(path.relative_to(app)) for path in required if not path.is_file()]
if (resources / 'UserGuide.html').exists():
    invalid.append('Contents/Resources/UserGuide.html would hide the localized guides')
if info.get('CFBundleLocalizations') != ['en', 'zh-Hans'] or info.get('LSHasLocalizedDisplayName') is not True:
    invalid.append('Info.plist localizations')
def read_strings(path):
    # Xcode writes compiled .strings as a UTF-16 XML plist whose declaration still says UTF-8, which plistlib
    # rejects; decode by BOM ourselves.
    try:
        data = path.read_bytes()
    except OSError:
        return {}
    if data.startswith(b'bplist'):
        return plistlib.loads(data)
    text = data.decode('utf-16') if data[:2] in (b'\xff\xfe', b'\xfe\xff') else data.decode('utf-8-sig')
    if text.lstrip().startswith('<?xml'):
        return plistlib.loads(re.sub(r'encoding="[^"]*"', 'encoding="UTF-8"', text, count=1).encode('utf-8'))
    return dict(re.findall(r'"((?:\\.|[^"\\])*)"\s*=\s*"((?:\\.|[^"\\])*)"\s*;', text))
try:
    names = read_strings(resources / 'zh-Hans.lproj/InfoPlist.strings')
except Exception:  # an unreadable file fails the check below
    names = {}
if names.get('CFBundleDisplayName') != '字体混搭':
    invalid.append('zh-Hans CFBundleDisplayName')
# D33: Donate… opens Afdian when the app runs in Simplified Chinese.
if names.get('FPDonateURL') != 'https://afdian.com/a/kciceblue':
    invalid.append('zh-Hans FPDonateURL')
check('localisations', not invalid, ', '.join(invalid))
main = contents / 'MacOS/Font Playground'
check('main architecture', run(['lipo', '-archs', main]).stdout.strip() == b'arm64')
sdk = run([root / 'scripts/check-sdk.sh', main])
print((sdk.stdout + sdk.stderr).decode(errors='replace').strip())
check('SDK', sdk.returncode == 0)
binaries = []
for path in contents.rglob('*'):
    if path.is_file() and not path.is_symlink() and b'Mach-O' in run(['file', '-b', path]).stdout:
        binaries.append(path)
bad_archs = [str(path) for path in binaries if run(['lipo', '-archs', path]).stdout.strip() != b'arm64']
check('all Mach-O architectures', not bad_archs, ', '.join(bad_archs))
bad_entitlements = []
for path in [app, *binaries]:
    result = run(['codesign', '-d', '--entitlements', '-', '--xml', path])
    if result.returncode:
        bad_entitlements.append(str(path) + ' (unsigned)')
        continue
    if result.stdout.strip():
        try:
            values = plistlib.loads(result.stdout)
        except ValueError:
            bad_entitlements.append(str(path) + ' (invalid entitlements)')
            continue
        allowed = {} if '--distribution' in options else {'com.apple.security.get-task-allow': True}
        if any(key not in allowed or allowed[key] != value for key, value in values.items()):
            bad_entitlements.append(str(path))
check('entitlements', not bad_entitlements, ', '.join(bad_entitlements))
runtime = resources / 'fpengine'
if runtime.is_dir():
    link = contents / 'Helpers/fpengine'
    check('helper symlink', link.is_symlink() and str(link.readlink()) == '../Resources/fpengine')
    result = run([link / 'bin/python3', '-I', '-B', '-c', 'import fpengine, fontTools, pathops, unicodedata2'])
    check('helper imports', result.returncode == 0, result.stderr.decode(errors='replace'))
    stripped = ['include', 'share', 'lib/pkgconfig', 'lib/python3.12/config-3.12-darwin',
                'lib/python3.12/tkinter', 'lib/python3.12/idlelib', 'lib/python3.12/ensurepip',
                'lib/python3.12/test', 'lib/python3.12/turtledemo', 'lib/libtcl*', 'lib/libtk*',
                'lib/python3.12/lib-dynload/_tkinter*']
    leftovers = [path for pattern in stripped for path in glob.glob(str(runtime / pattern))]
    leftovers += [str(path) for path in runtime.rglob('*.a')]
    check('stripped runtime', not leftovers, ', '.join(leftovers))
else:
    check('helper required for release', '--release' not in options)
invalid = []
for location in [contents / 'MacOS', contents / 'Frameworks', contents / 'Helpers']:
    if location.exists():
        invalid += [str(path) for path in location.rglob('*') if path.is_dir() and not path.is_symlink() and '.' in path.name]
check('code directory layout', not invalid, ', '.join(invalid))
if '--release' in options and runtime.is_dir():
    result = run([runtime / 'bin/python3', '-I', '-B', root / 'tools/release/collect_licenses.py', '--app', app, '--repo', root, '--check'])
    print((result.stdout + result.stderr).decode(errors='replace').strip())
    check('licences', result.returncode == 0)
if '--distribution' in options:
    result = run(['codesign', '--verify', '--deep', '--strict', app])
    check('distribution signature', result.returncode == 0, result.stderr.decode(errors='replace'))
    # TOOLING-1: terse display omits the certificate authority even for Developer ID signatures.
    metadata = run(['codesign', '-dv', '--verbose=4', app]).stderr
    check('Developer ID and timestamp', b'Authority=Developer ID Application' in metadata and b'Timestamp=' in metadata)
    invalid = [str(path) for path in binaries if not re.search(rb'flags=.*runtime', run(['codesign', '-dv', path]).stderr)]
    check('hardened runtime', not invalid, ', '.join(invalid))
print('check-bundle: ' + (str(len(problems)) + ' problems' if problems else 'OK'))
raise SystemExit(1 if problems else 0)
PY
