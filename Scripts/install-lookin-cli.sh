#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  install-lookin-cli.sh [package-dir]

Environment:
  INSTALL_PREFIX   Install location for the movable package. Default: /usr/local/ivista-lookin-cli
  BIN_DIR          Directory for the lookin symlink. Default: /usr/local/bin
  SUDO             Privilege command. Default: sudo

Examples:
  ./install.sh
  INSTALL_PREFIX="$HOME/.local/ivista-lookin-cli" BIN_DIR="$HOME/.local/bin" SUDO= ./install.sh
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
SOURCE_DIR="${1:-}"
INSTALL_PREFIX="${INSTALL_PREFIX:-/usr/local/ivista-lookin-cli}"
BIN_DIR="${BIN_DIR:-/usr/local/bin}"
SUDO="${SUDO-sudo}"

if [[ -z "${SOURCE_DIR}" ]]; then
  if [[ -x "${SCRIPT_DIR}/lookin" ]]; then
    SOURCE_DIR="${SCRIPT_DIR}"
  elif [[ -x "${PWD}/lookin" ]]; then
    SOURCE_DIR="${PWD}"
  else
    SOURCE_DIR="$(find "${ROOT_DIR}/build/LookinCLI" -maxdepth 1 -type d -name 'lookin-cli-macos-*' 2>/dev/null | sort | tail -n 1 || true)"
  fi
fi

if [[ -z "${SOURCE_DIR}" || ! -x "${SOURCE_DIR}/lookin" ]]; then
  echo "error: package dir with executable lookin not found" >&2
  echo "hint: run Scripts/build-lookin-cli.sh first, or pass an unpacked package dir." >&2
  exit 1
fi

if [[ ! -d "${SOURCE_DIR}/Frameworks" ]]; then
  echo "error: ${SOURCE_DIR}/Frameworks not found" >&2
  exit 1
fi

echo "==> Installing LookinCLI from ${SOURCE_DIR}"
${SUDO} mkdir -p "${INSTALL_PREFIX}" "${BIN_DIR}"
${SUDO} rm -rf "${INSTALL_PREFIX}/Frameworks"
${SUDO} cp -f "${SOURCE_DIR}/lookin" "${INSTALL_PREFIX}/lookin"
${SUDO} cp -R "${SOURCE_DIR}/Frameworks" "${INSTALL_PREFIX}/Frameworks"
${SUDO} ln -sf "${INSTALL_PREFIX}/lookin" "${BIN_DIR}/lookin"

echo "Installed: ${BIN_DIR}/lookin -> ${INSTALL_PREFIX}/lookin"
"${BIN_DIR}/lookin" --version
