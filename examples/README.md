# Example recipes

`fixtures/latin-cjk.fontrecipe` uses the generated, open synthetic Fixture Sans and Fixture CJK fonts. Its deliberately absent file paths resolve by PostScript name through `--font-dir`. Run from the repository root:

```sh
make setup
d=$(mktemp -d)
engine/.venv/bin/python -m fpengine.testing.make_fonts "$d/fonts"
FP_ENGINE_PYTHON="$PWD/engine/.venv/bin/python" swift run --package-path Packages/FontPlaygroundKit fpctl forge examples/fixtures/latin-cjk.fontrecipe --font-dir "$d/fonts" --out "$d/out.ttf"
```

`latin-cjk.fontrecipe` uses Helvetica Neue and PingFang SC on macOS. Its placeholder PingFang asset path exercises portable resolution: the CLI scans the installed font folders and matches the PostScript name. No font files ship with these recipes.

```sh
FP_ENGINE_PYTHON="$PWD/engine/.venv/bin/python" swift run --package-path Packages/FontPlaygroundKit fpctl forge examples/latin-cjk.fontrecipe --out /tmp/x.ttf
```

Use `--json` for a machine-readable report, `--quiet` to hide build progress, and `--font-dir` to search additional folders. Missing fonts are listed and stop a build by default. `--allow-missing` explicitly builds without them and reports their identities. Press Control-C to cancel and clean up the helper process.
