#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PREFLIGHT="$SCRIPT_DIR/prepare-notarization.sh"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

failures=0
tmp_files=()

cleanup() {
  local path
  for path in "${tmp_files[@]}"; do
    rm -f "$path"
  done
}
trap cleanup EXIT

pass() {
  printf 'ok %s\n' "$1"
}

fail() {
  printf 'FAIL %s\n' "$1" >&2
  failures=$((failures + 1))
}

new_key_path() {
  local path
  path="$(mktemp)"
  tmp_files+=("$path")
  rm -f "$path"
  printf '%s\n' "$path"
}

run_preflight() {
  local key_path="${1:-}"
  shift || true
  env -i \
    PATH="$PATH" \
    NOTARY_KEY_PATH="$key_path" \
    APPLE_ID="${APPLE_ID-}" \
    APPLE_TEAM_ID="${APPLE_TEAM_ID-}" \
    APPLE_APP_PASSWORD="${APPLE_APP_PASSWORD-}" \
    APPLE_API_KEY_BASE64="${APPLE_API_KEY_BASE64-}" \
    APPLE_API_KEY_ID="${APPLE_API_KEY_ID-}" \
    APPLE_API_ISSUER="${APPLE_API_ISSUER-}" \
    bash "$PREFLIGHT" --preflight
}

expect_mode() {
  local name="$1"
  local want="$2"
  local key_path stdout stderr status
  key_path="$(new_key_path)"
  stderr="$(mktemp)"
  tmp_files+=("$stderr")
  set +e
  stdout="$(run_preflight "$key_path" 2>"$stderr")"
  status=$?
  set -e
  if [[ "$status" -ne 0 || "$stdout" != "$want" ]]; then
    fail "$name (status=$status stdout=$stdout)"
    cat "$stderr" >&2
    return
  fi
  pass "$name"
}

expect_error() {
  local name="$1"
  local pattern="$2"
  local key_path stdout stderr status
  key_path="$(new_key_path)"
  stderr="$(mktemp)"
  tmp_files+=("$stderr")
  set +e
  stdout="$(run_preflight "$key_path" 2>"$stderr")"
  status=$?
  set -e
  local err
  err="$(cat "$stderr")"
  if [[ "$status" -eq 0 ]]; then
    fail "$name (expected failure, stdout=$stdout)"
    return
  fi
  if [[ "$stdout" == *apple-id* || "$stdout" == *api-key* ]]; then
    fail "$name (printed a mode on failure: $stdout)"
    return
  fi
  if [[ "$err" != *"$pattern"* ]]; then
    fail "$name (missing '$pattern')"
    printf '%s\n' "$err" >&2
    return
  fi
  if [[ "$err" == *"xxxx-xxxx"* || "$err" == *"BEGIN PRIVATE KEY"* ]]; then
    fail "$name leaked secret material"
    return
  fi
  pass "$name"
}

APPLE_ID=' person@example.com '
APPLE_TEAM_ID=$'ABCDE12345\n'
APPLE_APP_PASSWORD='xxxx-xxxx-xxxx-xxxx'
APPLE_API_KEY_BASE64=
APPLE_API_KEY_ID=
APPLE_API_ISSUER=
expect_mode "trimmed Apple ID secrets stay local" "apple-id"

APPLE_TEAM_ID='ABCDE1234'
expect_error "short team ID never contacts Apple" "Apple was not contacted"

APPLE_ID='"person@example.com"'
APPLE_TEAM_ID='ABCDE12345'
expect_error "quoted Apple ID is rejected locally" "without quotes"

APPLE_ID='not-an-email'
expect_error "Apple ID must look like an email" "bare Apple ID email"

pem='-----BEGIN PRIVATE KEY-----
AAAA
-----END PRIVATE KEY-----'
key_b64="$(printf '%s\n' "$pem" | base64 | tr -d '\n')"
wrapped_b64="$(printf '%s\n' "$key_b64" | fold -w 76)"
APPLE_API_KEY_BASE64="$wrapped_b64"
APPLE_API_KEY_ID='AB12CD34EF'
APPLE_API_ISSUER='aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
APPLE_ID='person@example.com'
APPLE_TEAM_ID='ABCDE12345'
APPLE_APP_PASSWORD='xxxx-xxxx-xxxx-xxxx'
key_path="$(new_key_path)"
stderr="$(mktemp)"
tmp_files+=("$stderr")
set +e
stdout="$(run_preflight "$key_path" 2>"$stderr")"
status=$?
set -e
if [[ "$status" -ne 0 || "$stdout" != "api-key" ]]; then
  fail "API key wins over a present Apple ID (status=$status stdout=$stdout)"
  cat "$stderr" >&2
elif ! grep -q "PRIVATE KEY" "$key_path"; then
  fail "API key was not decoded to the requested path"
else
  pass "API key wins over a present Apple ID"
fi
rm -f "$key_path"

APPLE_API_KEY_ID=
expect_error "partial API key does not fall back to Apple ID" "together"

APPLE_API_KEY_ID='AB12CD34EF'
APPLE_API_ISSUER='not-a-uuid'
expect_error "issuer must be a UUID" "issuer UUID"

APPLE_API_ISSUER='aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
APPLE_API_KEY_BASE64='!!!!'
expect_error "invalid API key base64 is rejected" "APPLE_API_KEY_BASE64"

for workflow in "$ROOT/.github/workflows/dev-release.yml" "$ROOT/.github/workflows/release.yml"; do
  if ! grep -q 'bash .github/scripts/prepare-notarization.sh' "$workflow"; then
    fail "$(basename "$workflow") does not call prepare-notarization.sh"
  elif ! grep -q 'APPLE_API_KEY_BASE64:' "$workflow"; then
    fail "$(basename "$workflow") does not pass the API key secret"
  else
    pass "$(basename "$workflow") delegates notarization setup"
  fi
done

if [[ "$failures" -ne 0 ]]; then
  printf '%s failure(s)\n' "$failures" >&2
  exit 1
fi
