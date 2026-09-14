#!/usr/bin/env bash
# Generate Kotlin UniFFI bindings from the compiled ffi crate.
# Run after build-android.sh or any cargo build that produces libspectra_core (host).
# Output: kotlin/app/src/main/kotlin/uniffi/
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FFI_DIR="${REPO_ROOT}/ffi"
CARGO_TARGET_DIR="${REPO_ROOT}/target"
BINDGEN_MANIFEST="${REPO_ROOT}/tools/uniffi-bindgen/Cargo.toml"
HOST_DYLIB="${CARGO_TARGET_DIR}/debug/libspectra_core.dylib"
OUT_DIR="${REPO_ROOT}/kotlin/app/src/main/kotlin/uniffi"

export PATH="${HOME}/.cargo/bin:/opt/homebrew/bin:/usr/local/bin:${PATH}"
if [[ -f "${HOME}/.cargo/env" ]]; then source "${HOME}/.cargo/env"; fi

echo "Building ffi crate (host)..."
CARGO_TARGET_DIR="${CARGO_TARGET_DIR}" cargo build --manifest-path "${FFI_DIR}/Cargo.toml"

mkdir -p "${OUT_DIR}"
echo "Generating Kotlin bindings..."
# Optimized generator against the debug dylib, for the reason bindgen-ios.sh
# gives: the profile of neither one reaches the generated bindings.
CARGO_TARGET_DIR="${CARGO_TARGET_DIR}" cargo run --release --manifest-path "${BINDGEN_MANIFEST}" \
  -- generate --language kotlin --library "${HOST_DYLIB}" --out-dir "${OUT_DIR}"

echo "Kotlin bindings written to ${OUT_DIR}"
