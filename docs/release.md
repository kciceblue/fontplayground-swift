# Releasing Font Playground

Run releases on an Apple silicon Mac with macOS 14 or later, Xcode 26 or later,
`xcodegen`, and the pinned `uv` from `scripts/tool-versions.env`. Start from a clean
checkout. `App/Version.xcconfig` and `engine/pyproject.toml` must name the same version.
The release script checks this before replacing its generated `build/release` and `dist` folders.

## Test the package locally

```bash
make setup lint test
scripts/release.sh --adhoc
```

This creates `dist/FontPlayground-<version>-arm64.dmg` and its `.sha256`. The pipeline
builds the embedded interpreter, checks the SDK and bundle, runs the headless test,
signs inside-out, tests again, creates the DMG, then mounts it read-only and tests
the mounted app. It does not install fonts or copy the app into Applications.
An ad-hoc image is for local testing; it has no Developer ID or notarization ticket.

For a faster development check:

```bash
make helper-runtime app self-test
scripts/check-bundle.sh "build/DerivedData/Build/Products/Debug/Font Playground.app"
scripts/tests/test_crit_1_check_sdk.sh
scripts/tests/test_tooling_1_sign_adhoc.sh
```

The app accepts `--self-test-report /existing/folder/report.jsonl` and
`--self-test-keep`. Reports are JSON Lines. Exit codes are 0 (passed), 1 (step failed),
2 (usage), 3 (unusable environment), and 4 (overall timeout). The default timeout is
180 seconds; `--self-test-timeout` accepts 10–3600 seconds. A release test adds
`--require-embedded-engine`. Debug-only `FP_SELF_TEST_INJECT_FAILURE=verify` checks
the failure path. A failed report write is printed on stderr without changing the test result.

## Prepare Developer ID signing

The account holder needs an active Apple Developer Program membership. Create a
**Developer ID Application** certificate using the account's Certificates page or
Xcode's certificate manager. Keep its private key with the certificate; Keychain
Access can export both as a password-protected `.p12`. Record the full identity
from `security find-identity -v -p codesigning`. Follow Apple's
[Developer ID certificate instructions](https://developer.apple.com/help/account/certificates/create-developer-id-certificates).

Create an App Store Connect API key authorized to submit notarization requests.
Download its `.p8` key and retain the key ID and issuer ID. Store credentials in a
local keychain profile instead of including their values in repository files:

```bash
xcrun notarytool store-credentials fp-notary \
  --key /private/path/AuthKey.p8 --key-id YOUR_KEY_ID --issuer YOUR_ISSUER_ID
NOTARY_KEYCHAIN_PROFILE=fp-notary scripts/release.sh \
  --identity "Developer ID Application: Your Name (TEAMID)"
```

Alternatively supply `NOTARY_KEY_PATH`, `NOTARY_KEY_ID`, and `NOTARY_ISSUER_ID` in
the environment. The release script notarizes and staples the app before creating
the DMG, then signs, notarizes, and staples the DMG. Both Gatekeeper assessments
must report `source=Notarized Developer ID`. See Apple's
[notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow).

## Configure GitHub releases

Add these six repository Actions secrets:

| Secret | Value |
|---|---|
| `MACOS_DEVELOPER_ID_P12_BASE64` | Base64-encoded certificate and private key `.p12` |
| `MACOS_DEVELOPER_ID_P12_PASSWORD` | Password used to export that `.p12` |
| `MACOS_DEVELOPER_ID_IDENTITY` | Full Developer ID Application identity |
| `NOTARY_API_KEY_P8_BASE64` | Base64-encoded App Store Connect `.p8` key |
| `NOTARY_API_KEY_ID` | Key ID |
| `NOTARY_API_ISSUER_ID` | Issuer ID |

Set them with the GitHub CLI. Without `--body`, `gh secret set` prompts for the
value, so it stays out of your shell history:

```bash
base64 -i /private/path/DeveloperID.p12 | gh secret set MACOS_DEVELOPER_ID_P12_BASE64
gh secret set MACOS_DEVELOPER_ID_P12_PASSWORD
gh secret set MACOS_DEVELOPER_ID_IDENTITY
base64 -i /private/path/AuthKey_KEYID.p8 | gh secret set NOTARY_API_KEY_P8_BASE64
gh secret set NOTARY_API_KEY_ID
gh secret set NOTARY_API_ISSUER_ID
gh secret list
```

The Release workflow runs on the self-hosted Mac mini (`[self-hosted, macOS, ARM64,
kcice-ci, kcice-build]`, see [self-hosted CI](self-hosted-ci.md)). Pull requests
always build ad hoc and never import release secrets. For a manual run,
`adhoc: true` is the default; set it to false to exercise Developer ID signing and
notarization. A manual run uses the committed version. A signed run first checks
that all six secrets are set and names any that are missing. A `v*.*.*` tag
additionally checks the tag version and creates a **draft** GitHub release, using
`docs/release/notes/<tag>.md` as its description when that file exists (GitHub's
generated list of merged pull requests otherwise). The build number is the
workflow's run number plus 100, above the 1.0.0 candidates (builds 1–4) built
from the private development repository. The signing step names its temporary
keychain (`CODESIGN_KEYCHAIN`), because a fleet job's fresh `HOME` keeps no
keychain search list. Actions are pinned to full commit hashes. The temporary
keychain, private-key files, and original keychain search list are cleaned up
even after failure. A billing-blocked workflow is pending, not passing.

## Publish a release

1. Set the same version in `App/Version.xcconfig` (`MARKETING_VERSION`) and
   `engine/pyproject.toml`, and write `docs/release/notes/vX.Y.Z.md`: English first,
   then 简体中文, with the donation links. Merge that to `main`.
2. Tag the merged commit and push the tag:

   ```bash
   git switch main && git pull --ff-only
   git tag -a vX.Y.Z -m "Font Playground X.Y.Z"
   git push origin vX.Y.Z
   ```

3. Wait for the Release workflow to create the draft. Download its DMG in a browser,
   so it is quarantined, and check it on a clean current macOS (and macOS 14 unless
   waived): `shasum -a 256 -c` against the attached `.sha256`, launch, run
   `"/Applications/Font Playground.app/Contents/MacOS/Font Playground" --self-test --require-embedded-engine`,
   and install and uninstall a Latin + CJK font.
4. Publish the draft. If the build is wrong, delete the draft and the tag
   (`git push origin :refs/tags/vX.Y.Z`), fix `main`, and tag again. Never move a
   tag after its release is published.

## Diagnose a rejected submission

`scripts/notarize.sh` prints the submission JSON. If Apple rejects it, the script
fetches and prints the submission log before returning failure. Keep the submission
ID and retrieve the log again with:

```bash
xcrun notarytool log SUBMISSION_ID --keychain-profile fp-notary notary-log.json
```

Fix the specific reported executable, signature, timestamp, or entitlement issue,
then rebuild through `release.sh`. Do not add broad entitlements or sign with
`--deep`. Ad-hoc helper files intentionally omit hardened runtime because the
interpreter and binary wheels have no matching Team ID; Developer ID signing
enables hardened runtime on every Mach-O. The main app always has hardened runtime.

The helper physically resides in `Contents/Resources/fpengine`; the relative
`Contents/Helpers/fpengine` symlink preserves the launch path. Nothing in the
self-test writes into the bundle. Generated acknowledgements include all detected
component licences, checked by `tools/release/collect_licenses.py --check`.
