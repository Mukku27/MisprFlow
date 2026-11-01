#!/usr/bin/env bash
# Store notarization credentials in the temporary signing keychain.
#
# App Store Connect API key secrets win when all three are set:
#   APPLE_API_KEY_BASE64, APPLE_API_KEY_ID, APPLE_API_ISSUER
# Otherwise the Apple ID app-specific password is used:
#   APPLE_ID, APPLE_TEAM_ID, APPLE_APP_PASSWORD
#
# `--preflight` validates the secrets and does not contact Apple.
set -euo pipefail

preflight_only=0
if [[ "${1:-}" == "--preflight" ]]; then
  preflight_only=1
elif [[ $# -gt 0 ]]; then
  echo "Usage: $0 [--preflight]" >&2
  exit 2
fi

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

key_b64="$(trim "${APPLE_API_KEY_BASE64:-}")"
key_id="$(trim "${APPLE_API_KEY_ID:-}")"
issuer="$(trim "${APPLE_API_ISSUER:-}")"
apple_id="$(trim "${APPLE_ID:-}")"
team_id="$(trim "${APPLE_TEAM_ID:-}")"
app_password="$(trim "${APPLE_APP_PASSWORD:-}")"

mode=""
if [[ -n "$key_b64" || -n "$key_id" || -n "$issuer" ]]; then
  if [[ -z "$key_b64" || -z "$key_id" || -z "$issuer" ]]; then
    echo "::error::Set APPLE_API_KEY_BASE64, APPLE_API_KEY_ID, and APPLE_API_ISSUER together. A partial API key is not sent to Apple, and the Apple ID password is not used as a fallback." >&2
    exit 1
  fi
  if [[ ! "$key_id" =~ ^[A-Za-z0-9]{10}$ ]]; then
    echo "::error::APPLE_API_KEY_ID must be the 10-character App Store Connect key ID. Apple was not contacted." >&2
    exit 1
  fi
  if [[ ! "$issuer" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]]; then
    echo "::error::APPLE_API_ISSUER must be the App Store Connect issuer UUID. Apple was not contacted." >&2
    exit 1
  fi

  if [[ -n "${NOTARY_KEY_PATH:-}" ]]; then
    key_path="$NOTARY_KEY_PATH"
  elif [[ -n "${RUNNER_TEMP:-}" ]]; then
    key_path="$RUNNER_TEMP/AuthKey.p8"
  else
    echo "::error::RUNNER_TEMP is not set." >&2
    exit 1
  fi

  if ! printf '%s' "$key_b64" | tr -d '[:space:]' | base64 --decode > "$key_path"; then
    rm -f "$key_path"
    echo "::error::APPLE_API_KEY_BASE64 did not base64-decode. Encode the .p8 with: base64 -i AuthKey.p8 | pbcopy" >&2
    exit 1
  fi
  chmod 600 "$key_path"
  if [[ ! -s "$key_path" ]] || ! grep -q "PRIVATE KEY" "$key_path"; then
    rm -f "$key_path"
    echo "::error::APPLE_API_KEY_BASE64 did not decode to an App Store Connect API private key (.p8)." >&2
    exit 1
  fi
  mode="api-key"
else
  if [[ -z "$apple_id" || -z "$team_id" || -z "$app_password" ]]; then
    echo "::error::Missing notarization secrets. Set APPLE_ID, APPLE_TEAM_ID, and APPLE_APP_PASSWORD, or set APPLE_API_KEY_BASE64, APPLE_API_KEY_ID, and APPLE_API_ISSUER." >&2
    exit 1
  fi
  if [[ "$apple_id" == *"\""* || "$apple_id" == *"'"* || "$apple_id" != *"@"* || "$apple_id" == *" "* ]]; then
    echo "::error::APPLE_ID must be the bare Apple ID email used for Developer ID notarization, without quotes or spaces. Apple was not contacted." >&2
    exit 1
  fi
  if [[ ! "$team_id" =~ ^[A-Za-z0-9]{10}$ ]]; then
    echo "::error::APPLE_TEAM_ID must be the 10-character Apple Team ID. Apple was not contacted." >&2
    exit 1
  fi
  mode="apple-id"
fi

if [[ "$preflight_only" -eq 1 ]]; then
  printf '%s\n' "$mode"
  exit 0
fi

if [[ -z "${KEYCHAIN_PATH:-}" || ! -f "$KEYCHAIN_PATH" ]]; then
  echo "::error::Notarization setup ran without the temporary signing keychain." >&2
  exit 1
fi

if [[ "$mode" == "api-key" ]]; then
  echo "Using App Store Connect API key for notarization." >&2
  trap 'rm -f "$key_path"' EXIT
else
  echo "Using the Apple ID app-specific password for notarization." >&2
fi

set +e
if [[ "$mode" == "api-key" ]]; then
  output="$(xcrun notarytool store-credentials "notarytool-profile" \
    --key "$key_path" \
    --key-id "$key_id" \
    --issuer "$issuer" \
    --keychain "$KEYCHAIN_PATH" 2>&1)"
else
  output="$(xcrun notarytool store-credentials "notarytool-profile" \
    --apple-id "$apple_id" \
    --team-id "$team_id" \
    --password "$app_password" \
    --keychain "$KEYCHAIN_PATH" 2>&1)"
fi
status=$?
set -e

printf '%s\n' "$output"
if [[ "$status" -ne 0 ]]; then
  if [[ "$output" == *"401"* ]]; then
    echo "::error::Apple rejected notarization with HTTP 401. Unlock the Apple ID at https://iforgot.apple.com, then update APPLE_APP_PASSWORD or switch this workflow to an App Store Connect API key (APPLE_API_KEY_BASE64, APPLE_API_KEY_ID, APPLE_API_ISSUER). Do not re-run until those secrets change; every push to main contacts Apple again." >&2
    echo "Apple's 'Apple ID has been locked' text is returned after rejected app-specific-password attempts, including attempts from a GitHub-hosted Mac. A new app-specific password, or an App Store Connect API key, is required before the next run." >&2
  fi
  exit "$status"
fi

if [[ "$mode" == "api-key" ]]; then
  rm -f "$key_path"
fi
