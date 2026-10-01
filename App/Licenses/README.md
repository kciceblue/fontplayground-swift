# Bundled licence sources

These static texts supplement the app, CPython and wheel licences collected at build time. They are committed inputs; builds and tests never download them. `scripts/fetch-pbs-licenses.sh` is a maintainer-run command for a pinned runtime update and needs `zstd` (`brew install zstd`).

## Pinned runtime

- python-build-standalone release: `20260924`, CPython `3.12.14`, target `aarch64-apple-darwin`.
- Full archive: [cpython-3.12.14+20260924-aarch64-apple-darwin-pgo+lto-full.tar.zst](https://github.com/astral-sh/python-build-standalone/releases/download/20260924/cpython-3.12.14%2B20260924-aarch64-apple-darwin-pgo%2Blto-full.tar.zst).
- SHA-256: `0bcd6620de677cb12e19a987ab78603267d4c1173ed72ba082a91fe85ac36959`, verified against that release's `SHA256SUMS`.
- `LICENSE.{openssl-3,sqlite,mpdecimal,expat,liblzma,bzip2,libffi,libuuid}.txt` are copied byte for byte from `python/licenses/` in that archive, retaining the upstream names. `python/PYTHON.json` was inspected for the linked components. The library licence identifiers in `components.json` were checked against these texts.

## Other pinned sources

- `python-build-standalone/LICENSE.python-build-standalone.txt`: entire [build repository LICENSE](https://github.com/astral-sh/python-build-standalone/blob/6a729962cddc76630b59b1b895501b1539412524/LICENSE), MPL-2.0, release tag commit `6a729962cddc76630b59b1b895501b1539412524`. The full runtime archive does not include the build scripts' licence.
- `python-build-standalone/HACL-LICENSE.txt`: byte-identical leading licence comment from [CPython v3.12.14 Hacl_Hash_SHA2.c](https://github.com/python/cpython/blob/v3.12.14/Modules/_hacl/Hacl_Hash_SHA2.c), through the closing comment and its newline. The pinned `Doc/license.rst` contains no HACL notice, so the actual compiled source's MIT notice is used.
- `unicode/Unicode-LICENSE.txt`: full [Unicode License v3](https://www.unicode.org/license.txt), copyright 1991–2026, retrieved 2026-09-30. Its committed SHA-256 below pins this edition; update deliberately with the Unicode data version.
- `fpengine/otf2ttf-NOTICE.txt`: full MIT licence from the locked fontTools 4.66.0 wheel's `licenses/LICENSE`, Copyright (c) 2017 Just van Rossum. The same text is [fontTools 4.66.0 LICENSE](https://github.com/fonttools/fonttools/blob/4.66.0/LICENSE); attribution for the adapted `Snippets/otf2ttf.py` is in `Acknowledgements.txt` and `engine/src/fpengine/prepare.py`.
- Skia's Copyright (c) 2011 Google Inc. BSD-3-Clause notice is already included verbatim in the locked skia-pathops wheel's licence; the collector includes it automatically.

## Committed text checksums

These hashes record the exact upstream bytes that were reviewed.

```text
6787208f83f659ccbc2223b2fde952ffa6f7e8aca62f1a8a2bf5bc51bb1b2383  fpengine/otf2ttf-NOTICE.txt
998ce04fb8ad9dedb0bc1b44938f8c3dcf1089780fa105ce1c8c30fb5554d78c  python-build-standalone/HACL-LICENSE.txt
1f38bbc7caacafd65169276d759c0d88c991b753b643ce35d0e45ea1971dd441  python-build-standalone/LICENSE.bzip2.txt
122f2c27000472a201d337b9b31f7eb2b52d091b02857061a8880371612d9534  python-build-standalone/LICENSE.expat.txt
deaf3a42effb551a5b140fa9afefed183a27f1341c6d1bf430d106a5e6931fc0  python-build-standalone/LICENSE.libffi.txt
9a4062de0a2c388a98cf35a35d348b62fa97c838a71c3c28ee1a2d7d0a565b02  python-build-standalone/LICENSE.liblzma.txt
122ee1f7e258f2c3c0e538a75c037684f420454bf3850ddc74ce750bbf5fe86b  python-build-standalone/LICENSE.libuuid.txt
669512af7219f58be03a398766d7c9da11a3b3df9d3f05cb74c5ceca25c8da3b  python-build-standalone/LICENSE.mpdecimal.txt
7d5450cb2d142651b8afa315b5f238efc805dad827d91ba367d8516bc9d49e7a  python-build-standalone/LICENSE.openssl-3.txt
1f256ecad192880510e84ad60474eab7589218784b9a50bc7ceee34c2b91f1d5  python-build-standalone/LICENSE.python-build-standalone.txt
38bef3d28b24f145ea293bd3b6eb4b20396982abc8303128fb493986ea5bc719  python-build-standalone/LICENSE.sqlite.txt
e7a93b009565cfce55919a381437ac4db883e9da2126fa28b91d12732bc53d96  unicode/Unicode-LICENSE.txt
```
