#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  notarize-lookin-cli.sh <zip-path>

Environment:
  NOTARYTOOL_PROFILE            Optional keychain profile name created by xcrun notarytool store-credentials.
  APPLE_ID                      Apple ID email. Required when NOTARYTOOL_PROFILE is not set.
  APPLE_TEAM_ID                 Apple Developer Team ID. Required when NOTARYTOOL_PROFILE is not set.
  APPLE_APP_SPECIFIC_PASSWORD   App-specific password. Required when NOTARYTOOL_PROFILE is not set.

Notes:
  - The zip should be signed with Developer ID before notarization.
  - Zip archives can be submitted to Apple's notary service, but they cannot be stapled.
  - For stapling, distribute a notarized .dmg or .pkg instead.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -ne 1 ]]; then
  usage >&2
  exit 2
fi

ZIP_PATH="$1"
[[ -f "${ZIP_PATH}" ]] || {
  echo "error: zip not found: ${ZIP_PATH}" >&2
  exit 1
}

if [[ -n "${NOTARYTOOL_PROFILE:-}" ]]; then
  xcrun notarytool submit "${ZIP_PATH}" --keychain-profile "${NOTARYTOOL_PROFILE}" --wait
else
  : "${APPLE_ID:?APPLE_ID is required when NOTARYTOOL_PROFILE is not set}"
  : "${APPLE_TEAM_ID:?APPLE_TEAM_ID is required when NOTARYTOOL_PROFILE is not set}"
  : "${APPLE_APP_SPECIFIC_PASSWORD:?APPLE_APP_SPECIFIC_PASSWORD is required when NOTARYTOOL_PROFILE is not set}"
  xcrun notarytool submit "${ZIP_PATH}" \
    --apple-id "${APPLE_ID}" \
    --team-id "${APPLE_TEAM_ID}" \
    --password "${APPLE_APP_SPECIFIC_PASSWORD}" \
    --wait
fi

