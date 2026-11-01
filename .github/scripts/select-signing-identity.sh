#!/usr/bin/env bash
# Read `security find-identity` output on stdin and print one
# "Developer ID Application: ..." identity name on stdout.
#
# Exit codes:
#   0  an identity was selected (stderr may contain a warning)
#   2  this output has no Developer ID Application identity
#   3  the only Developer ID Application identity is expired
#   4  a Developer ID Application identity is present but unusable
set -euo pipefail

summary_re='^[[:space:]]*[0-9]+[[:space:]]+(valid[[:space:]]+)?identities[[:space:]]+found[[:space:]]*$'
identity_re='^[[:space:]]*[0-9]+\)[[:space:]]+[0-9A-Fa-f]+[[:space:]]+"([^"]+)"(.*)$'

valid_name=""
untrusted_name=""
expired_name=""
broken_name=""
broken_reason=""
saw_other=0

while IFS= read -r line || [[ -n "$line" ]]; do
  line="${line%$'\r'}"
  if [[ -z "${line//[[:space:]]/}" ]]; then
    continue
  fi
  if [[ "$line" =~ $summary_re ]]; then
    continue
  fi
  if [[ ! "$line" =~ $identity_re ]]; then
    continue
  fi

  name="${BASH_REMATCH[1]}"
  rest="${BASH_REMATCH[2]}"
  if [[ "$name" != "Developer ID Application:"* ]]; then
    saw_other=1
    continue
  fi

  if [[ "$rest" == *EXPIRED* ]]; then
    expired_name="$name"
    continue
  fi
  if [[ "$rest" == *NOT_TRUSTED* || "$rest" == *"not trusted"* ]]; then
    if [[ -z "$untrusted_name" ]]; then
      untrusted_name="$name"
    fi
    continue
  fi
  if [[ "$rest" =~ [^[:space:]] ]]; then
    broken_name="$name"
    broken_reason="$rest"
    continue
  fi
  if [[ -z "$valid_name" ]]; then
    valid_name="$name"
  fi
done

if [[ -n "$valid_name" ]]; then
  printf '%s\n' "$valid_name"
  exit 0
fi

if [[ -n "$untrusted_name" ]]; then
  echo "::warning::The Developer ID certificate and private key are in the keychain, but macOS did not mark the identity valid. Signing will use the certificate name. This is the macOS 26 temporary-keychain trust check, not a missing .p12." >&2
  printf '%s\n' "$untrusted_name"
  exit 0
fi

if [[ -n "$expired_name" ]]; then
  echo "::error::The Developer ID Application certificate in DEVELOPER_ID_CERTIFICATE_BASE64 is expired. Renew it in the Apple Developer account, export a new .p12 that includes the private key, and update DEVELOPER_ID_CERTIFICATE_BASE64 and DEVELOPER_ID_CERTIFICATE_PASSWORD." >&2
  exit 3
fi

if [[ -n "$broken_name" ]]; then
  echo "::error::A Developer ID Application identity was imported but macOS rejected it (${broken_reason# }). Re-export the current certificate and its private key as one .p12." >&2
  exit 4
fi

if [[ "$saw_other" -eq 1 ]]; then
  echo "::error::The imported certificate is not a Developer ID Application certificate. Notarized releases require a Developer ID Application identity, exported with its private key." >&2
  exit 2
fi

echo "::error::No codesigning identity was imported. The summary line from \`security find-identity\` is not an identity. Export the Developer ID Application certificate together with its private key as one .p12, base64-encode it, and update DEVELOPER_ID_CERTIFICATE_BASE64." >&2
exit 2
