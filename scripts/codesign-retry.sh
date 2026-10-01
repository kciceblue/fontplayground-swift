#!/bin/bash
# Runs codesign, retrying only when Apple's timestamp service refuses the request. On 2026-09-30 it refused
# about one request in fifteen, and a release signs over a hundred files one at a time (WP-701).
set -uo pipefail
attempts=${CODESIGN_ATTEMPTS:-5}
# CI imports the identity into its own keychain. A fleet job's fresh HOME keeps no keychain search list, so codesign
# finds the identity only when told which keychain holds it.
keychain=()
[[ -z "${CODESIGN_KEYCHAIN:-}" ]] || keychain=(--keychain "$CODESIGN_KEYCHAIN")
for ((attempt = 1; ; attempt++)); do
  output=$(codesign ${keychain[@]+"${keychain[@]}"} "$@" 2>&1)
  status=$?
  [[ -z "$output" ]] || echo "$output" >&2
  if [[ $status -eq 0 || "$output" != *'The timestamp service is not available'* || $attempt -ge $attempts ]]; then
    exit "$status"
  fi
  echo "codesign-retry: the timestamp service refused the request; retrying ($attempt of $((attempts - 1)))" >&2
  sleep "${CODESIGN_RETRY_DELAY:-$attempt}"
done
