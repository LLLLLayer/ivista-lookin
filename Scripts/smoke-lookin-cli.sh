#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  smoke-lookin-cli.sh [ivista-lookin-bin-or-package-dir]

Environment:
  IVISTA_LOOKIN_BIN   Path to ivista-lookin. Default: auto-detect package/Debug/system ivista-lookin.
  BUNDLE_ID           Optional target app bundle id for device smoke tests.
  TRANSPORT           Optional app selector: simulator or usb.
  PORT                Optional app selector port.
  DEVICE_ID           Optional app selector device id.
  QUERY               Query used by find smoke test. Default: UILabel
  OID                 Optional oid used by tree --oid and inspect smoke tests.
  SET_ATTR            Optional attribute identifier used by set --dry-run when OID is set.
  SET_VALUE           Optional value used by set --dry-run when OID and SET_ATTR are set.
  REQUIRE_APP         Set to 1 to fail when no reachable target app is found.
  SKIP_DEVICE_TESTS   Set to 1 to run only local command smoke tests.
  OUT_DIR             Optional output directory for captured JSON.

Examples:
  ./Scripts/smoke-lookin-cli.sh
  BUNDLE_ID=com.example.demo TRANSPORT=usb ./Scripts/smoke-lookin-cli.sh
  ./Scripts/smoke-lookin-cli.sh build/LookinCLI/ivista-lookin-macos-universal
  IVISTA_LOOKIN_BIN=build/LookinCLI/ivista-lookin-macos-universal/ivista-lookin BUNDLE_ID=com.example.demo OID=130 ./Scripts/smoke-lookin-cli.sh
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

if [[ $# -gt 1 ]]; then
  usage >&2
  exit 2
fi

CLI_NAME="ivista-lookin"
IVISTA_LOOKIN_BIN="${IVISTA_LOOKIN_BIN:-}"
CLI_PATH_ARG="${1:-}"
BUNDLE_ID="${BUNDLE_ID:-}"
TRANSPORT="${TRANSPORT:-}"
PORT="${PORT:-}"
DEVICE_ID="${DEVICE_ID:-}"
QUERY="${QUERY:-UILabel}"
OID="${OID:-}"
SET_ATTR="${SET_ATTR:-}"
SET_VALUE="${SET_VALUE:-}"
REQUIRE_APP="${REQUIRE_APP:-0}"
SKIP_DEVICE_TESTS="${SKIP_DEVICE_TESTS:-0}"
OUT_DIR="${OUT_DIR:-}"

TEMP_OUT_DIR=""
if [[ -z "${OUT_DIR}" ]]; then
  TEMP_OUT_DIR="$(mktemp -d)"
  OUT_DIR="${TEMP_OUT_DIR}"
fi

cleanup() {
  if [[ -n "${TEMP_OUT_DIR}" ]]; then
    rm -rf "${TEMP_OUT_DIR}"
  fi
}
trap cleanup EXIT

log() {
  printf '==> %s\n' "$*"
}

warn() {
  printf 'warning: %s\n' "$*" >&2
}

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

normalize_cli_bin() {
  local path="$1"
  if [[ -d "${path}" ]]; then
    path="${path}/${CLI_NAME}"
  fi
  printf '%s\n' "${path}"
}

detect_cli_bin() {
  if [[ -n "${CLI_PATH_ARG}" ]]; then
    normalize_cli_bin "${CLI_PATH_ARG}"
    return
  fi

  if [[ -n "${IVISTA_LOOKIN_BIN}" ]]; then
    normalize_cli_bin "${IVISTA_LOOKIN_BIN}"
    return
  fi

  local candidates=(
    "${ROOT_DIR}/build/LookinCLI/ivista-lookin-macos-universal/${CLI_NAME}"
    "${ROOT_DIR}/build/LookinCLI/ivista-lookin-macos-arm64/${CLI_NAME}"
    "${ROOT_DIR}/build/LookinCLI/ivista-lookin-macos-x86_64/${CLI_NAME}"
    "${ROOT_DIR}/DerivedData/LookinCLI/Build/Products/Debug/${CLI_NAME}"
  )

  for candidate in "${candidates[@]}"; do
    if [[ -x "${candidate}" ]]; then
      printf '%s\n' "${candidate}"
      return
    fi
  done

  if command -v "${CLI_NAME}" >/dev/null 2>&1; then
    command -v "${CLI_NAME}"
    return
  fi

  fail "${CLI_NAME} executable not found; set IVISTA_LOOKIN_BIN or run xcodebuild/Scripts/build-lookin-cli.sh first"
}

validate_json_file() {
  local file="$1"
  /usr/bin/ruby -rjson -e 'JSON.parse(File.read(ARGV.fetch(0)))' "${file}" >/dev/null
}

json_first_bundle_id() {
  local file="$1"
  /usr/bin/ruby -rjson -e '
    data = JSON.parse(File.read(ARGV.fetch(0)))
    app = data.find { |item| item["bundleIdentifier"].to_s.length > 0 }
    print(app ? app["bundleIdentifier"] : "")
  ' "${file}"
}

selector_args=()
if [[ -n "${TRANSPORT}" ]]; then
  selector_args+=(--transport "${TRANSPORT}")
fi
if [[ -n "${PORT}" ]]; then
  selector_args+=(--port "${PORT}")
fi
if [[ -n "${DEVICE_ID}" ]]; then
  selector_args+=(--device-id "${DEVICE_ID}")
fi

CLI_BIN="$(detect_cli_bin)"
[[ -x "${CLI_BIN}" ]] || fail "${CLI_NAME} is not executable: ${CLI_BIN}"

log "Using ${CLI_BIN}"

log "Local command smoke tests"
"${CLI_BIN}" --version >/dev/null
"${CLI_BIN}" --help | grep -q "ivista-lookin find"
"${CLI_BIN}" tree --help | grep -q -- "--filter"
"${CLI_BIN}" find --help | grep -q "Find hierarchy"
"${CLI_BIN}" set --help | grep -q "custom"
"${CLI_BIN}" doctor >/dev/null

if [[ "${SKIP_DEVICE_TESTS}" == "1" ]]; then
  log "Skipping device smoke tests"
  exit 0
fi

log "Fetching apps"
apps_json="${OUT_DIR}/apps.json"
if ! "${CLI_BIN}" apps --json "${selector_args[@]}" > "${apps_json}"; then
  if [[ "${REQUIRE_APP}" == "1" ]]; then
    fail "${CLI_NAME} apps failed"
  fi
  warn "${CLI_NAME} apps failed; skipping device smoke tests"
  exit 0
fi
validate_json_file "${apps_json}"

if [[ -z "${BUNDLE_ID}" ]]; then
  BUNDLE_ID="$(json_first_bundle_id "${apps_json}")"
fi

if [[ -z "${BUNDLE_ID}" ]]; then
  if [[ "${REQUIRE_APP}" == "1" ]]; then
    fail "no reachable app found"
  fi
  warn "no reachable app found; skipping hierarchy smoke tests"
  exit 0
fi

app_args=(--bundle-id "${BUNDLE_ID}" "${selector_args[@]}")
log "Device command smoke tests for ${BUNDLE_ID}"

tree_json="${OUT_DIR}/tree.json"
"${CLI_BIN}" tree "${app_args[@]}" --depth 1 --json > "${tree_json}"
validate_json_file "${tree_json}"

find_json="${OUT_DIR}/find.json"
"${CLI_BIN}" find "${app_args[@]}" "${QUERY}" --limit 5 --json > "${find_json}"
validate_json_file "${find_json}"

if [[ -n "${OID}" ]]; then
  tree_oid_json="${OUT_DIR}/tree-oid.json"
  "${CLI_BIN}" tree "${app_args[@]}" --oid "${OID}" --depth 1 --json > "${tree_oid_json}"
  validate_json_file "${tree_oid_json}"

  inspect_json="${OUT_DIR}/inspect.json"
  "${CLI_BIN}" inspect "${app_args[@]}" --oid "${OID}" --json > "${inspect_json}"
  validate_json_file "${inspect_json}"

  attrs_json="${OUT_DIR}/attrs.json"
  "${CLI_BIN}" attrs "${app_args[@]}" --oid "${OID}" --json > "${attrs_json}"
  validate_json_file "${attrs_json}"

  if [[ -n "${SET_ATTR}" && -n "${SET_VALUE}" ]]; then
    set_json="${OUT_DIR}/set-dry-run.json"
    "${CLI_BIN}" set "${app_args[@]}" --oid "${OID}" --attr "${SET_ATTR}" --value "${SET_VALUE}" --dry-run --json > "${set_json}"
    validate_json_file "${set_json}"
  fi
fi

log "Smoke tests passed"
if [[ -z "${TEMP_OUT_DIR}" ]]; then
  log "Output: ${OUT_DIR}"
fi
