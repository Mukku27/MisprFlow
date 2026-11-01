#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SELECTOR="$SCRIPT_DIR/select-signing-identity.sh"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DEVELOPER_ID='Developer ID Application: Example Person (ABCDE12345)'

failures=0

pass() {
  printf 'ok %s\n' "$1"
}

fail() {
  printf 'FAIL %s\n' "$1" >&2
  failures=$((failures + 1))
}

expect_identity() {
  local name="$1"
  local input="$2"
  local stdout stderr status
  stderr="$(mktemp)"
  set +e
  stdout="$(printf '%s\n' "$input" | "$SELECTOR" 2>"$stderr")"
  status=$?
  set -e
  if [[ "$status" -ne 0 || "$stdout" != "$DEVELOPER_ID" ]]; then
    fail "$name (status=$status stdout=$stdout)"
    cat "$stderr" >&2
  else
    pass "$name"
  fi
  rm -f "$stderr"
}

expect_failure() {
  local name="$1"
  local input="$2"
  local pattern="$3"
  local want_status="${4:-}"
  local stdout stderr status
  stderr="$(mktemp)"
  set +e
  stdout="$(printf '%s\n' "$input" | "$SELECTOR" 2>"$stderr")"
  status=$?
  set -e
  local err
  err="$(cat "$stderr")"
  rm -f "$stderr"
  if [[ "$status" -eq 0 || -n "$stdout" ]]; then
    fail "$name (expected no identity, status=$status stdout=$stdout)"
    printf '%s\n' "$err" >&2
    return
  fi
  if [[ -n "$want_status" && "$status" -ne "$want_status" ]]; then
    fail "$name (status=$status, want $want_status)"
    printf '%s\n' "$err" >&2
    return
  fi
  if [[ "$err" != *"$pattern"* ]]; then
    fail "$name (missing '$pattern')"
    printf '%s\n' "$err" >&2
    return
  fi
  pass "$name"
}

expect_identity "valid Developer ID identity" \
"  1) ABCDEF1234567890ABCDEF1234567890ABCDEF12 \"$DEVELOPER_ID\"
     1 valid identities found"

expect_failure "logged zero-valid summary is not an identity" \
"     0 valid identities found" \
"No codesigning identity" \
2

expect_identity "macOS 26 untrusted identity is still selected" \
"  1) ABCDEF1234567890ABCDEF1234567890ABCDEF12 \"$DEVELOPER_ID\" (CSSMERR_TP_NOT_TRUSTED)
     1 identities found
     0 valid identities found"

expect_failure "expired Developer ID is rejected" \
"  1) ABCDEF1234567890ABCDEF1234567890ABCDEF12 \"$DEVELOPER_ID\" (CSSMERR_TP_CERT_EXPIRED)
     1 identities found
     0 valid identities found" \
"expired" \
3

expect_failure "development certificate is not used for release" \
'  1) ABCDEF1234567890ABCDEF1234567890ABCDEF12 "Apple Development: Example Person (ABCDE12345)"
     1 valid identities found' \
"not a Developer ID Application" \
2

expect_identity "Developer ID wins when a development identity is listed first" \
"  1) AAAA111122223333444455556666777788889999 \"Apple Development: Example Person (ABCDE12345)\"
  2) ABCDEF1234567890ABCDEF1234567890ABCDEF12 \"$DEVELOPER_ID\"
     2 valid identities found"

expect_failure "unknown identity error is rejected" \
"  1) ABCDEF1234567890ABCDEF1234567890ABCDEF12 \"$DEVELOPER_ID\" (CSSMERR_TP_INVALID_ANCHOR)
     1 identities found" \
"INVALID_ANCHOR" \
4

expect_failure "empty find-identity output" "" "No codesigning identity" 2

for workflow in "$ROOT/.github/workflows/dev-release.yml" "$ROOT/.github/workflows/release.yml"; do
  if ! grep -q 'bash .github/scripts/prepare-signing.sh' "$workflow"; then
    fail "$(basename "$workflow") does not call prepare-signing.sh"
  elif grep -q 'find-identity' "$workflow"; then
    fail "$(basename "$workflow") still parses find-identity inline"
  else
    pass "$(basename "$workflow") delegates signing setup"
  fi
done

if [[ "$failures" -ne 0 ]]; then
  printf '%s failure(s)\n' "$failures" >&2
  exit 1
fi
