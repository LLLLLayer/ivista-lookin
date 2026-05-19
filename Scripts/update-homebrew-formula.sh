#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  update-homebrew-formula.sh <version> <zip-url> [zip-path]

Environment:
  FORMULA_PATH  Formula path. Default: Formula/ivista-lookin.rb

Examples:
  ./Scripts/update-homebrew-formula.sh v0.1.1 \
    https://github.com/LLLLLayer/ivista-lookin/releases/download/v0.1.1/ivista-lookin-macos-universal.zip

  ./Scripts/update-homebrew-formula.sh v0.1.1 \
    https://github.com/LLLLLayer/ivista-lookin/releases/download/v0.1.1/ivista-lookin-macos-universal.zip \
    build/LookinCLI/ivista-lookin-macos-universal.zip
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -lt 2 || $# -gt 3 ]]; then
  usage >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

VERSION_INPUT="$1"
ZIP_URL="$2"
ZIP_PATH="${3:-${ROOT_DIR}/build/LookinCLI/ivista-lookin-macos-universal.zip}"
FORMULA_PATH="${FORMULA_PATH:-${ROOT_DIR}/Formula/ivista-lookin.rb}"

if [[ ! -f "${ZIP_PATH}" ]]; then
  echo "error: zip not found: ${ZIP_PATH}" >&2
  exit 1
fi

if [[ ! -f "${FORMULA_PATH}" ]]; then
  echo "error: formula not found: ${FORMULA_PATH}" >&2
  exit 1
fi

VERSION="${VERSION_INPUT#v}"
SHA256="$(shasum -a 256 "${ZIP_PATH}" | awk '{print $1}')"

ruby - "${FORMULA_PATH}" "${ZIP_URL}" "${VERSION}" "${SHA256}" <<'RUBY'
path, url, version, sha256 = ARGV
content = File.read(path)
content = content.sub(/^\s*url ".*"$/, "  url \"#{url}\"")
content = content.sub(/^\s*version ".*"$/, "  version \"#{version}\"")
content = content.sub(/^\s*sha256 ".*"$/, "  sha256 \"#{sha256}\"")
File.write(path, content)
RUBY

echo "Updated ${FORMULA_PATH}"
echo "  url: ${ZIP_URL}"
echo "  version: ${VERSION}"
echo "  sha256: ${SHA256}"
