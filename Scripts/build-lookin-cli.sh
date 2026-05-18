#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

CONFIGURATION="${CONFIGURATION:-Release}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-${ROOT_DIR}/DerivedData/LookinCLIRelease}"
OUTPUT_DIR="${OUTPUT_DIR:-${ROOT_DIR}/build/LookinCLI}"
XCODEBUILD="${XCODEBUILD:-xcodebuild}"
WORKSPACE="${WORKSPACE:-${ROOT_DIR}/Lookin.xcworkspace}"
SCHEME="${SCHEME:-LookinCLI}"

echo "==> Building ${SCHEME} (${CONFIGURATION})"
"${XCODEBUILD}" \
  -workspace "${WORKSPACE}" \
  -scheme "${SCHEME}" \
  -configuration "${CONFIGURATION}" \
  -derivedDataPath "${DERIVED_DATA_PATH}" \
  build

PRODUCT_DIR="${DERIVED_DATA_PATH}/Build/Products/${CONFIGURATION}"

echo "==> Packaging LookinCLI"
PRODUCT_DIR="${PRODUCT_DIR}" \
OUTPUT_DIR="${OUTPUT_DIR}" \
"${SCRIPT_DIR}/package-lookin-cli.sh"

