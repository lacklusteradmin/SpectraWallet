#!/usr/bin/env bash
# Generate Swift UniFFI bindings from the compiled ffi crate.
# Run after build-ios.sh or any cargo build that produces libspectra_core.dylib (host).
# Output: swift/generated/
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FFI_DIR="${REPO_ROOT}/ffi"
CARGO_TARGET_DIR="${REPO_ROOT}/target"
BINDGEN_MANIFEST="${REPO_ROOT}/tools/uniffi-bindgen/Cargo.toml"
HOST_DYLIB="${CARGO_TARGET_DIR}/debug/libspectra_core.dylib"
OUT_DIR="${REPO_ROOT}/swift/generated"

export PATH="${HOME}/.cargo/bin:/opt/homebrew/bin:/usr/local/bin:${PATH}"
if [[ -f "${HOME}/.cargo/env" ]]; then source "${HOME}/.cargo/env"; fi

echo "Building ffi crate (host)..."
CARGO_TARGET_DIR="${CARGO_TARGET_DIR}" cargo build --manifest-path "${FFI_DIR}/Cargo.toml"

mkdir -p "${OUT_DIR}"
echo "Generating Swift bindings..."
CARGO_TARGET_DIR="${CARGO_TARGET_DIR}" cargo run --manifest-path "${BINDGEN_MANIFEST}" \
  -- generate --language swift --library "${HOST_DYLIB}" --out-dir "${OUT_DIR}"

cp "${OUT_DIR}/spectra_coreFFI.modulemap" "${OUT_DIR}/module.modulemap"

# Patch for Swift 6 MainActor isolation. Write the temp file OUTSIDE OUT_DIR so
# Xcode's synchronized root group can't catch a transient .!NNNN! ghost.
PATCH_TMP="$(mktemp -t spectra_core.swift.XXXXXX)"
sed \
  -e 's/@escaping UniffiRustFutureContinuationCallback/UniffiRustFutureContinuationCallback/g' \
  -e 's/^fileprivate func uniffiFutureContinuationCallback/nonisolated fileprivate func uniffiFutureContinuationCallback/' \
  "${OUT_DIR}/spectra_core.swift" > "${PATCH_TMP}"
mv "${PATCH_TMP}" "${OUT_DIR}/spectra_core.swift"

echo "Swift bindings written to ${OUT_DIR}"
