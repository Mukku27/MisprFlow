#!/usr/bin/env bash
# Import the Developer ID .p12 into a temporary keychain and export
# CODESIGN_IDENTITY plus KEYCHAIN_PATH for the rest of the job.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SELECTOR="$SCRIPT_DIR/select-signing-identity.sh"

if [[ -z "${GITHUB_ENV:-}" ]]; then
  echo "::error::GITHUB_ENV is not set." >&2
  exit 1
fi
if [[ -z "${RUNNER_TEMP:-}" ]]; then
  echo "::error::RUNNER_TEMP is not set." >&2
  exit 1
fi
if [[ -z "${CERTIFICATE_BASE64:-}" ]]; then
  echo "::error::Missing DEVELOPER_ID_CERTIFICATE_BASE64 secret. Export the Developer ID .p12 as base64 and set it with: base64 -i certificate.p12 | pbcopy && gh secret set DEVELOPER_ID_CERTIFICATE_BASE64 --repo \"${GITHUB_REPOSITORY:-<owner>/<repo>}\"" >&2
  exit 1
fi
if [[ -z "${CERTIFICATE_PASSWORD:-}" ]]; then
  echo "::error::Missing DEVELOPER_ID_CERTIFICATE_PASSWORD secret. Set it with: gh secret set DEVELOPER_ID_CERTIFICATE_PASSWORD --repo \"${GITHUB_REPOSITORY:-<owner>/<repo>}\"" >&2
  exit 1
fi

CERTIFICATE_PATH="$RUNNER_TEMP/developer_id.p12"
KEYCHAIN_PATH="$RUNNER_TEMP/signing.keychain-db"
KEYCHAIN_PASSWORD="$(openssl rand -hex 20)"
PARTITION_LOG="$RUNNER_TEMP/keychain-partition.txt"
IDENTITY_ERR="$RUNNER_TEMP/signing-identity-error.txt"
intermediate_path="$RUNNER_TEMP/DeveloperIDG2CA.cer"
# Apple's published Developer ID Certification Authority (G2) certificate.
# https://www.apple.com/certificateauthority/DeveloperIDG2CA.cer
intermediate_sha256="f16cd3c54c7f83cea4bf1a3e6a0819c8aaa8e4a1528fd144715f350643d2df3a"

rm -f "$CERTIFICATE_PATH" "$PARTITION_LOG" "$IDENTITY_ERR" "$intermediate_path"
trap 'rm -f "$CERTIFICATE_PATH" "$intermediate_path" "$PARTITION_LOG" "$IDENTITY_ERR"' EXIT

if ! printf '%s' "$CERTIFICATE_BASE64" | tr -d '[:space:]' | base64 --decode > "$CERTIFICATE_PATH"; then
  echo "::error::DEVELOPER_ID_CERTIFICATE_BASE64 did not base64-decode. Re-export the .p12 and reset the secret. Line wrapping is removed before decoding." >&2
  exit 1
fi
if [[ ! -s "$CERTIFICATE_PATH" ]]; then
  echo "::error::Decoded .p12 is empty. Re-export the .p12 and reset DEVELOPER_ID_CERTIFICATE_BASE64." >&2
  exit 1
fi

security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"

# macOS 26 evaluates `find-identity -v` against the temporary keychain
# alone. The Developer ID intermediate has to be in that keychain or a
# real certificate is reported as "0 valid identities found".
intermediate_url="https://www.apple.com/certificateauthority/DeveloperIDG2CA.cer"
if curl --fail --silent --show-error --location --retry 3 --retry-delay 2 --max-time 60 \
  --output "$intermediate_path" "$intermediate_url"; then
  actual_sha="$(openssl x509 -in "$intermediate_path" -inform DER -noout -fingerprint -sha256 2>/dev/null | tr -d ':\n' | tr 'A-F' 'a-f' || true)"
  actual_sha="${actual_sha##*=}"
  actual_sha="${actual_sha//[[:space:]]/}"
  if [[ "$actual_sha" != "$intermediate_sha256" ]]; then
    echo "::warning::Developer ID intermediate fingerprint did not match Apple's published certificate. Skipping import." >&2
  elif ! security import "$intermediate_path" -k "$KEYCHAIN_PATH" >/dev/null; then
    echo "::warning::Could not import the Developer ID intermediate certificate into the temporary keychain." >&2
  fi
  rm -f "$intermediate_path"
else
  echo "::warning::Could not download the Developer ID intermediate certificate. Identity validation will continue with the .p12 alone." >&2
fi

# stdout can include private-key attributes. Keep it out of the job log.
if ! security import "$CERTIFICATE_PATH" \
  -P "$CERTIFICATE_PASSWORD" \
  -A \
  -t cert \
  -f pkcs12 \
  -k "$KEYCHAIN_PATH" > "$PARTITION_LOG"; then
  echo "::error::Could not import the Developer ID .p12. Confirm DEVELOPER_ID_CERTIFICATE_PASSWORD matches the file and that the .p12 contains the certificate and its private key." >&2
  exit 1
fi
rm -f "$CERTIFICATE_PATH"

keychains=("$KEYCHAIN_PATH")
while IFS= read -r keychain_line; do
  keychain_line="${keychain_line#"${keychain_line%%[![:space:]]*}"}"
  keychain_line="${keychain_line%"${keychain_line##*[![:space:]]}"}"
  keychain_line="${keychain_line#\"}"
  keychain_line="${keychain_line%\"}"
  if [[ -n "$keychain_line" && "$keychain_line" != "$KEYCHAIN_PATH" ]]; then
    keychains+=("$keychain_line")
  fi
done < <(security list-keychains -d user)
keychains+=("/Library/Keychains/System.keychain")
security list-keychains -d user -s "${keychains[@]}"
security default-keychain -s "$KEYCHAIN_PATH"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"

# The partition-list listing includes private-key attributes. Keep it out
# of the job log; only record whether a private key was imported.
security set-key-partition-list -S apple-tool:,apple:,codesign: \
  -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH" >> "$PARTITION_LOG"

valid_out="$(security find-identity -v -p codesigning "$KEYCHAIN_PATH" || true)"
all_out="$(security find-identity -p codesigning "$KEYCHAIN_PATH" || true)"

set +e
SELECTED="$(printf '%s\n' "$valid_out" | "$SELECTOR" 2>"$IDENTITY_ERR")"
status=$?
set -e
if [[ "$status" -ne 0 ]]; then
  set +e
  SELECTED="$(printf '%s\n' "$all_out" | "$SELECTOR" 2>"$IDENTITY_ERR")"
  status=$?
  set -e
fi

if [[ "$status" -ne 0 ]]; then
  cat "$IDENTITY_ERR" >&2
  echo "security find-identity -v -p codesigning:" >&2
  printf '%s\n' "$valid_out" >&2
  echo "security find-identity -p codesigning:" >&2
  printf '%s\n' "$all_out" >&2
  if grep -q "Imported Private Key" "$PARTITION_LOG"; then
    echo "The temporary keychain has an imported private key." >&2
  else
    echo "::error::The .p12 did not import a private key. Re-export the Developer ID Application certificate and its private key together." >&2
  fi
  echo "Certificate labels in the temporary keychain:" >&2
  security find-certificate -a "$KEYCHAIN_PATH" 2>/dev/null | grep '"labl"' || true
  exit 1
fi

if [[ -s "$IDENTITY_ERR" ]]; then
  cat "$IDENTITY_ERR" >&2
fi

printf 'Found signing identity: %s\n' "$SELECTED"
{
  printf 'CODESIGN_IDENTITY=%s\n' "$SELECTED"
  printf 'KEYCHAIN_PATH=%s\n' "$KEYCHAIN_PATH"
} >> "$GITHUB_ENV"
