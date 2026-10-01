# Font Playground: the single entry point for setup, lint, test and build (docs/testing.md §1).
# macOS only (ADR-0014). Works with the system GNU Make 3.81 (/usr/bin/make).
SHELL := /bin/bash
.DEFAULT_GOAL := test

UNAME_S := $(shell uname -s)
ifneq ($(UNAME_S),Darwin)
$(error Font Playground builds and tests on macOS only (docs/development.md))
endif

UV ?= uv
SWIFT ?= swift
XCODEGEN ?= xcodegen
FP_CODESIGN_IDENTITY ?= -
FP_DEVELOPMENT_TEAM ?=
XCODEBUILD_FLAGS ?= -quiet

KIT := Packages/FontPlaygroundKit
MACKIT := Packages/FontPlaygroundMacKit
DERIVED := build/DerivedData
APP := $(DERIVED)/Build/Products/Debug/Font Playground.app
PY_DIRS := engine $(wildcard tools)

export FP_ENGINE_PYTHON ?= $(CURDIR)/engine/.venv/bin/python

.PHONY: setup lint engine-test engine-apple-fonts conformance conformance-check kit-test mac-test test app \
	helper-runtime self-test _need-uv

_need-uv:
	@command -v "$(UV)" >/dev/null 2>&1 || { \
	  echo "error: uv not found. Install it with 'brew install uv' (see https://docs.astral.sh/uv/)." >&2; \
	  exit 1; }

setup: _need-uv
	cd engine && "$(UV)" sync --frozen
	scripts/check-macos-toolchain.sh --warn

lint: _need-uv
	"$(UV)" run --project engine --frozen ruff check $(PY_DIRS)
	"$(UV)" run --project engine --frozen ruff format --check $(PY_DIRS)
	"$(SWIFT)" format lint --strict --recursive $(KIT) $(MACKIT) App/Sources

engine-test: _need-uv
	cd engine && "$(UV)" run --frozen pytest -q

engine-apple-fonts: _need-uv
	cd engine && FP_APPLE_FONTS=1 "$(UV)" run --frozen pytest -q -m apple_fonts

conformance: _need-uv
	@if [ -f tools/conformance/generate.py ]; then \
	  set -x; "$(UV)" run --project engine --frozen python tools/conformance/generate.py; \
	else echo "conformance: tools/conformance/generate.py does not exist yet (WP-202); nothing to generate"; fi

conformance-check: conformance
	git diff --exit-code -- spec/fixtures Packages/FontPlaygroundKit/Sources/FPCore/Generated
	@untracked="$$(git ls-files --others --exclude-standard -- spec/fixtures Packages/FontPlaygroundKit/Sources/FPCore/Generated)"; \
	if [ -n "$$untracked" ]; then echo "error: new, uncommitted fixtures:" >&2; echo "$$untracked" >&2; exit 1; fi

kit-test:
	"$(SWIFT)" test --package-path $(KIT)

mac-test:
	"$(SWIFT)" test $(SWIFT_TEST_FLAGS) --package-path $(MACKIT)

test: engine-test conformance-check kit-test mac-test

app:
	scripts/check-macos-toolchain.sh
	"$(XCODEGEN)" generate --spec App/project.yml --quiet
	xcodebuild -project App/FontPlayground.xcodeproj -scheme FontPlayground -configuration Debug \
	  -derivedDataPath $(DERIVED) $(XCODEBUILD_FLAGS) build \
	  CODE_SIGN_IDENTITY="$(FP_CODESIGN_IDENTITY)" DEVELOPMENT_TEAM="$(FP_DEVELOPMENT_TEAM)"

helper-runtime:
	@if [ -x scripts/build-helper-runtime.sh ]; then scripts/build-helper-runtime.sh; \
	else echo "error: scripts/build-helper-runtime.sh does not exist yet (WP-203)" >&2; exit 2; fi

self-test: app
	"$(APP)/Contents/MacOS/Font Playground" --self-test
