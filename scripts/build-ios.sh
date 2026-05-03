#!/usr/bin/env bash
# Compile the ffi crate for iOS targets and lipo-merge into universal static libraries.
# Usage: scripts/build-ios.sh [--release]
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FFI_DIR="${REPO_ROOT}/ffi"
CARGO_TARGET_DIR="${REPO_ROOT}/target"
OUT_DIR="${REPO_ROOT}/build/apple"

PROFILE="debug"
PROFILE_FLAG=""
if [[ "${1:-}" == "--release" ]]; then
  PROFILE="release"
  PROFILE_FLAG="--release"
fi

export PATH="${HOME}/.cargo/bin:/opt/homebrew/bin:/usr/local/bin:${PATH}"
if [[ -f "${HOME}/.cargo/env" ]]; then source "${HOME}/.cargo/env"; fi

rustup target add aarch64-apple-ios 2>/dev/null || true
# Simulator targets (uncomment to restore):
# rustup target add aarch64-apple-ios-sim x86_64-apple-ios 2>/dev/null || true

for target in aarch64-apple-ios; do
  # Simulator targets (uncomment to restore):
  # for target in aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios; do
  echo "Building ${target}..."
  CARGO_TARGET_DIR="${CARGO_TARGET_DIR}" cargo build \
    --manifest-path "${FFI_DIR}/Cargo.toml" \
    --target "${target}" \
    ${PROFILE_FLAG}
done

DEVICE_OUT="${OUT_DIR}/ios-device"
mkdir -p "${DEVICE_OUT}"
# Simulator output (uncomment to restore):
# SIM_OUT="${OUT_DIR}/ios-simulator"
# mkdir -p "${SIM_OUT}" "${DEVICE_OUT}"
# lipo -create \
#   "${CARGO_TARGET_DIR}/aarch64-apple-ios-sim/${PROFILE}/libspectra_core.a" \
#   "${CARGO_TARGET_DIR}/x86_64-apple-ios/${PROFILE}/libspectra_core.a" \
#   -output "${SIM_OUT}/libspectra_core.a"

cp "${CARGO_TARGET_DIR}/aarch64-apple-ios/${PROFILE}/libspectra_core.a" \
   "${DEVICE_OUT}/libspectra_core.a"

echo "iOS libraries written to ${OUT_DIR}"
