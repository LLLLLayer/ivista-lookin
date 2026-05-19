#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  verify-lookin-cli-release.sh [zip-path]

Environment:
  ZIP_PATH            Release zip path. Default: build/LookinCLI/lookin-cli-macos-universal.zip
  BUNDLE_ID           Optional target app bundle id for device smoke tests.
  TRANSPORT           Optional app selector: simulator or usb.
  PORT                Optional app selector port.
  DEVICE_ID           Optional app selector device id.
  QUERY               Query used by find smoke test. Default: UILabel
  OID                 Optional oid used by tree/inspect/attrs smoke tests.
  SET_ATTR            Optional attribute identifier used by set --dry-run when OID is set.
  SET_VALUE           Optional value used by set --dry-run when OID and SET_ATTR are set.
  REQUIRE_APP         Set to 1 to fail when no reachable target app is found.
  SKIP_DEVICE_TESTS   Set to 1 to run only local command smoke tests.
  OUT_DIR             Optional output directory for captured JSON.

Examples:
  ./Scripts/verify-lookin-cli-release.sh
  REQUIRE_APP=1 BUNDLE_ID=com.example.demo TRANSPORT=usb ./Scripts/verify-lookin-cli-release.sh
  OID=130 SET_ATTR=l_f_f SET_VALUE='0,0,120,44' ./Scripts/verify-lookin-cli-release.sh build/LookinCLI/lookin-cli-macos-universal.zip
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -gt 1 ]]; then
  usage >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

ZIP_PATH="${1:-${ZIP_PATH:-${ROOT_DIR}/build/LookinCLI/lookin-cli-macos-universal.zip}}"

log() {
  printf '==> %s\n' "$*"
}

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

has_rpath() {
  local binary="$1"
  local rpath="$2"
  otool -l "${binary}" | awk '/LC_RPATH/{flag=1; next} flag && /path /{print $2; flag=0}' | grep -Fxq "${rpath}"
}

[[ -f "${ZIP_PATH}" ]] || fail "release zip not found: ${ZIP_PATH}"

TMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

log "Checksum"
shasum -a 256 "${ZIP_PATH}"

log "Unzipping release package"
/usr/bin/unzip -q "${ZIP_PATH}" -d "${TMP_DIR}"

LOOKIN_BIN="$(find "${TMP_DIR}" -mindepth 2 -maxdepth 2 -type f -name lookin -perm -111 | head -n 1)"
[[ -n "${LOOKIN_BIN}" ]] || fail "lookin executable not found in zip"

PACKAGE_DIR="$(cd "$(dirname "${LOOKIN_BIN}")" && pwd)"
[[ -d "${PACKAGE_DIR}/Frameworks/LookinShared.framework" ]] || fail "LookinShared.framework missing"
[[ -d "${PACKAGE_DIR}/Frameworks/ReactiveObjC.framework" ]] || fail "ReactiveObjC.framework missing"
[[ -f "${PACKAGE_DIR}/install.sh" ]] || fail "install.sh missing"
[[ -f "${PACKAGE_DIR}/README.md" ]] || fail "README.md missing"

log "Verifying binary layout"
has_rpath "${LOOKIN_BIN}" "@executable_path/Frameworks" || fail "missing @executable_path/Frameworks rpath"
codesign --verify --deep "${LOOKIN_BIN}"

log "Running smoke tests from unpacked package"
LOOKIN_BIN="${LOOKIN_BIN}" "${SCRIPT_DIR}/smoke-lookin-cli.sh"

log "Release verification passed: ${PACKAGE_DIR}"
