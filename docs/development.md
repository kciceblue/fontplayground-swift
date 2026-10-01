# Development

For embedded-runtime packaging, signing, notarization and DMG checks, see the
[release runbook](release.md).

Font Playground has a Python engine, a Foundation-only Swift package, and a native macOS app. Everything builds and tests on macOS only ([ADR-0014](adr/0014-macos-only.md)). Read [architecture.md](architecture.md) and [AGENTS.md](../AGENTS.md) before changing code. Work packages, their dependencies and acceptance criteria are listed in [plan.md](plan.md).

## Prerequisites

Use macOS 14 or newer on Apple silicon, Xcode 26 or newer, and XcodeGen 2.42.0 or newer. Install Xcode from the App Store, select it, then install the command-line dependencies:

```sh
sudo xcode-select -s /Applications/Xcode.app
brew install uv xcodegen
```

Use the uv version in [`scripts/tool-versions.env`](../scripts/tool-versions.env). The engine enforces its compatible minor version through `required-version`. If a newer Homebrew uv falls outside that range, install the pinned version from [uv's versioned installation instructions](https://docs.astral.sh/uv/getting-started/installation/#installing-specific-versions), or update the repository's pins together as described below.

macOS does not provide a `python` command, and `/usr/bin/python3` may be Python 3.9, which is too old for this engine. `make setup` lets uv fetch Python 3.12 from [`.python-version`](../.python-version), create `engine/.venv`, and install the committed lockfile. There is no separate pip or editable-install step.

## Set up and verify

Run these commands at the repository root:

```sh
make setup
make lint
make test
```

Setup needs network access to download Python and the locked dependencies. Later build and test commands need no network. `UV_OFFLINE=1 make lint test` explicitly disables uv's network use once setup has populated its cache.

`make test` runs the engine tests, the conformance check, and both Swift packages' tests. The default engine suite skips real Apple fonts; `make engine-apple-fonts` opts into those tests. Tests report their skip reasons. See [testing.md](testing.md) for every Make target, test marker, environment variable and fixture rule.

At WP-001, the Swift modules and app are placeholders: `make conformance` reports that WP-202 has not supplied the generator, `make helper-runtime` reports that WP-203 has not supplied the embedded runtime, and `make self-test` checks only the shell until WP-601 implements the full pipeline.

## Build and run the macOS app

```sh
make app
make self-test
open "build/DerivedData/Build/Products/Debug/Font Playground.app"
```

`make app` checks the selected Xcode and XcodeGen versions, generates the project and builds the Debug app. `make self-test` builds if needed, then runs the headless smoke test. To work in Xcode after generating the project:

```sh
open App/FontPlayground.xcodeproj
```

Edit `App/project.yml` and the Swift sources, then regenerate through `make app`. The generated project, build outputs, virtual environment and DMGs stay out of Git.

The Make targets export `FP_ENGINE_PYTHON` as the absolute path to `engine/.venv/bin/python`. The Xcode scheme sets the same development override. The helper client, `fpctl` and tests use it to locate a Python interpreter that can import `fpengine`. When using those tools directly, set an absolute path, for example:

```sh
export FP_ENGINE_PYTHON="$PWD/engine/.venv/bin/python"
```

Development builds default to ad-hoc signing. To keep privacy grants across rebuilds, use a stable Apple Development identity and your team identifier:

```sh
make app FP_CODESIGN_IDENTITY="Apple Development" FP_DEVELOPMENT_TEAM=YOUR_TEAM_ID
```

See [ADR-0010](adr/0010-distribution.md) for signing and distribution policy.

## Safe tests and reproducible tools

Tests use temporary directories for fonts, Application Support, caches and output. They never write into a user's real font folders or Font Playground's real support/cache folders. CoreText registrations are process scope only, and font descriptors come from file URLs. Name lookups for fonts that are not installed can trigger system downloads and are forbidden. The two reviewed exceptions are documented in [architecture.md](architecture.md).

Tests do not access the network or open visible windows. UI logic is tested off-screen; appearance and VoiceOver checks are manual. Do not commit Apple or Microsoft fonts. Small open-licence fixtures must satisfy [testing.md §4](testing.md#4-fixtures-policy) and be listed in `engine/tests/data/README.md`.

The pinned uv executable and its bundled `uv_build` backend must share a compatible minor version so offline wheel builds work. To update uv, change `UV_VERSION` in `scripts/tool-versions.env`, `tool.uv.required-version` and `build-system.requires` in `engine/pyproject.toml` together, then regenerate `engine/uv.lock` with network access in a work package that permits it. Commit all of those changes together.

Python formatting uses the root `ruff.toml`. Swift formatting uses the root `.swift-format`. CI runs every Make target on a self-hosted Mac ([self-hosted-ci.md](self-hosted-ci.md)).

To hand a work package to a coding agent on the Mac, follow [dispatch.md](dispatch.md).
