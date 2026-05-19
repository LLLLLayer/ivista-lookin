#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  package-lookin-cli.sh

Environment:
  PRODUCT_DIR      Xcode build product dir. Default: DerivedData/LookinCLIRelease/Build/Products/Release
  OUTPUT_DIR       Output root. Default: build/LookinCLI
  PACKAGE_NAME     Package directory and zip basename. Default: derived from ivista-lookin binary archs
  SKIP_CODESIGN    Set to 1 to skip ad-hoc signing.

The package contains ivista-lookin, Frameworks/, LICENSE, README.md, and install.sh.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

PRODUCT_DIR="${PRODUCT_DIR:-${ROOT_DIR}/DerivedData/LookinCLIRelease/Build/Products/Release}"
OUTPUT_DIR="${OUTPUT_DIR:-${ROOT_DIR}/build/LookinCLI}"
PACKAGE_NAME="${PACKAGE_NAME:-}"
SKIP_CODESIGN="${SKIP_CODESIGN:-0}"
CLI_NAME="ivista-lookin"

CLI_BIN="${PRODUCT_DIR}/${CLI_NAME}"

if [[ ! -x "${CLI_BIN}" ]]; then
  echo "error: executable not found: ${CLI_BIN}" >&2
  echo "hint: run Scripts/build-lookin-cli.sh first, or set PRODUCT_DIR." >&2
  exit 1
fi

if [[ -z "${PACKAGE_NAME}" ]]; then
  BINARY_ARCHS="$(lipo -archs "${CLI_BIN}" 2>/dev/null || uname -m)"
  if [[ "${BINARY_ARCHS}" == *"arm64"* && "${BINARY_ARCHS}" == *"x86_64"* ]]; then
    PACKAGE_ARCH="universal"
  else
    PACKAGE_ARCH="${BINARY_ARCHS// /-}"
  fi
  PACKAGE_NAME="ivista-lookin-macos-${PACKAGE_ARCH}"
fi

PACKAGE_DIR="${OUTPUT_DIR}/${PACKAGE_NAME}"
ZIP_PATH="${OUTPUT_DIR}/${PACKAGE_NAME}.zip"

rm -rf "${PACKAGE_DIR}" "${ZIP_PATH}"
mkdir -p "${PACKAGE_DIR}/Frameworks"

cp -f "${CLI_BIN}" "${PACKAGE_DIR}/${CLI_NAME}"

if [[ -d "${PRODUCT_DIR}/Frameworks" ]]; then
  cp -R "${PRODUCT_DIR}/Frameworks/." "${PACKAGE_DIR}/Frameworks/"
fi

for framework_name in LookinShared ReactiveObjC; do
  if [[ -d "${PRODUCT_DIR}/${framework_name}.framework" && ! -d "${PACKAGE_DIR}/Frameworks/${framework_name}.framework" ]]; then
    cp -R "${PRODUCT_DIR}/${framework_name}.framework" "${PACKAGE_DIR}/Frameworks/${framework_name}.framework"
  fi
  if [[ -d "${PRODUCT_DIR}/${framework_name}/${framework_name}.framework" && ! -d "${PACKAGE_DIR}/Frameworks/${framework_name}.framework" ]]; then
    cp -R "${PRODUCT_DIR}/${framework_name}/${framework_name}.framework" "${PACKAGE_DIR}/Frameworks/${framework_name}.framework"
  fi
done

if [[ ! -d "${PACKAGE_DIR}/Frameworks/LookinShared.framework" ]]; then
  echo "error: LookinShared.framework not found in product dir" >&2
  exit 1
fi

if [[ ! -d "${PACKAGE_DIR}/Frameworks/ReactiveObjC.framework" ]]; then
  echo "error: ReactiveObjC.framework not found in product dir" >&2
  exit 1
fi

cp -f "${ROOT_DIR}/LICENSE" "${PACKAGE_DIR}/LICENSE"
cp -f "${SCRIPT_DIR}/install-lookin-cli.sh" "${PACKAGE_DIR}/install.sh"

cat > "${PACKAGE_DIR}/README.md" <<'README'
# LookinCLI

Run from this directory:

```bash
./ivista-lookin --version
./ivista-lookin apps
```

Install into `/usr/local/bin/ivista-lookin`:

```bash
./install.sh
```

Install without sudo:

```bash
INSTALL_PREFIX="$HOME/.local/ivista-lookin-cli" BIN_DIR="$HOME/.local/bin" SUDO= ./install.sh
```

LookinCLI does not require Lookin.app to be installed, but the target iOS app still needs a compatible LookinServer integration.
README

has_rpath() {
  local binary="$1"
  local rpath="$2"
  otool -l "${binary}" | awk '/LC_RPATH/{flag=1; next} flag && /path /{print $2; flag=0}' | grep -Fxq "${rpath}"
}

if ! has_rpath "${PACKAGE_DIR}/${CLI_NAME}" "@executable_path/Frameworks"; then
  install_name_tool -add_rpath "@executable_path/Frameworks" "${PACKAGE_DIR}/${CLI_NAME}"
fi

if [[ "${SKIP_CODESIGN}" != "1" ]]; then
  codesign --force --deep --sign - "${PACKAGE_DIR}/${CLI_NAME}" >/dev/null
  find "${PACKAGE_DIR}/Frameworks" -maxdepth 1 -type d -name '*.framework' -print0 | while IFS= read -r -d '' framework; do
    codesign --force --deep --sign - "${framework}" >/dev/null
  done
fi

(
  cd "${OUTPUT_DIR}"
  /usr/bin/zip -qry --symlinks "${PACKAGE_NAME}.zip" "${PACKAGE_NAME}"
)

echo "Package dir: ${PACKAGE_DIR}"
echo "Package zip: ${ZIP_PATH}"
