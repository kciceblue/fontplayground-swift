#!/bin/bash
# Runs codesign, retrying only when Apple's timestamp service refuses the request. On 2026-09-30 it refused
# about one request in fifteen, and a release signs over a hundred files one at a time (WP-701).
set -uo pipefail
attempts=${CODESIGN_ATTEMPTS:-5}
for ((attempt = 1; ; attempt++)); do
  output=$(codesign "$@" 2>&1)
  status=$?
  [[ -z "$output" ]] || echo "$output" >&2
  if [[ $status -eq 0 || "$output" != *'The timestamp service is not available'* || $attempt -ge $attempts ]]; then
    exit "$status"
  fi
  echo "codesign-retry: the timestamp service refused the request; retrying ($attempt of $((attempts - 1)))" >&2
  sleep "${CODESIGN_RETRY_DELAY:-$attempt}"
done
