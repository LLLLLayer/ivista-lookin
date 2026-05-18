#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  smoke-lookin-cli.sh

Environment:
  LOOKIN_BIN          Path to lookin. Default: auto-detect Debug/package/system lookin.
  BUNDLE_ID           Optional target app bundle id for device smoke tests.
  TRANSPORT           Optional app selector: simulator or usb.
  PORT                Optional app selector port.
  DEVICE_ID           Optional app selector device id.
  QUERY               Query used by find smoke test. Default: UILabel
  OID                 Optional oid used by tree --oid and inspect smoke tests.
  REQUIRE_APP         Set to 1 to fail when no reachable target app is found.
  SKIP_DEVICE_TESTS   Set to 1 to run only local command smoke tests.
  OUT_DIR             Optional output directory for captured JSON.

Examples:
  ./Scripts/smoke-lookin-cli.sh
  BUNDLE_ID=com.example.demo TRANSPORT=usb ./Scripts/smoke-lookin-cli.sh
  LOOKIN_BIN=build/LookinCLI/lookin-cli-macos-universal/lookin BUNDLE_ID=com.example.demo OID=130 ./Scripts/smoke-lookin-cli.sh
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

LOOKIN_BIN="${LOOKIN_BIN:-}"
BUNDLE_ID="${BUNDLE_ID:-}"
TRANSPORT="${TRANSPORT:-}"
PORT="${PORT:-}"
DEVICE_ID="${DEVICE_ID:-}"
QUERY="${QUERY:-UILabel}"
OID="${OID:-}"
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

detect_lookin_bin() {
  if [[ -n "${LOOKIN_BIN}" ]]; then
    printf '%s\n' "${LOOKIN_BIN}"
    return
  fi

  local candidates=(
    "${ROOT_DIR}/DerivedData/LookinCLI/Build/Products/Debug/lookin"
    "${ROOT_DIR}/build/LookinCLI/lookin-cli-macos-universal/lookin"
    "${ROOT_DIR}/build/LookinCLI/lookin-cli-macos-arm64/lookin"
    "${ROOT_DIR}/build/LookinCLI/lookin-cli-macos-x86_64/lookin"
  )

  for candidate in "${candidates[@]}"; do
    if [[ -x "${candidate}" ]]; then
      printf '%s\n' "${candidate}"
      return
    fi
  done

  if command -v lookin >/dev/null 2>&1; then
    command -v lookin
    return
  fi

  fail "lookin executable not found; set LOOKIN_BIN or run xcodebuild/Scripts/build-lookin-cli.sh first"
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

LOOKIN_BIN="$(detect_lookin_bin)"
[[ -x "${LOOKIN_BIN}" ]] || fail "lookin is not executable: ${LOOKIN_BIN}"

log "Using ${LOOKIN_BIN}"

log "Local command smoke tests"
"${LOOKIN_BIN}" --version >/dev/null
"${LOOKIN_BIN}" --help | grep -q "lookin find"
"${LOOKIN_BIN}" tree --help | grep -q -- "--filter"
"${LOOKIN_BIN}" find --help | grep -q "Find hierarchy"
"${LOOKIN_BIN}" doctor >/dev/null

if [[ "${SKIP_DEVICE_TESTS}" == "1" ]]; then
  log "Skipping device smoke tests"
  exit 0
fi

log "Fetching apps"
apps_json="${OUT_DIR}/apps.json"
if ! "${LOOKIN_BIN}" apps --json "${selector_args[@]}" > "${apps_json}"; then
  if [[ "${REQUIRE_APP}" == "1" ]]; then
    fail "lookin apps failed"
  fi
  warn "lookin apps failed; skipping device smoke tests"
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
"${LOOKIN_BIN}" tree "${app_args[@]}" --depth 1 --json > "${tree_json}"
validate_json_file "${tree_json}"

find_json="${OUT_DIR}/find.json"
"${LOOKIN_BIN}" find "${app_args[@]}" "${QUERY}" --limit 5 --json > "${find_json}"
validate_json_file "${find_json}"

if [[ -n "${OID}" ]]; then
  tree_oid_json="${OUT_DIR}/tree-oid.json"
  "${LOOKIN_BIN}" tree "${app_args[@]}" --oid "${OID}" --depth 1 --json > "${tree_oid_json}"
  validate_json_file "${tree_oid_json}"

  inspect_json="${OUT_DIR}/inspect.json"
  "${LOOKIN_BIN}" inspect "${app_args[@]}" --oid "${OID}" --json > "${inspect_json}"
  validate_json_file "${inspect_json}"
fi

log "Smoke tests passed"
if [[ -z "${TEMP_OUT_DIR}" ]]; then
  log "Output: ${OUT_DIR}"
fi

