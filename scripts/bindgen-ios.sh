#!/usr/bin/env bash
# Generate the Swift UniFFI bindings, and apply the one patch they need.
#
# The single owner of `swift/generated/`. The Xcode "Build Rust Derivation
# Core" phase calls this rather than repeating it: the two used to generate
# separately and patch *differently*, so the checked-out bindings depended on
# which had run last — this script wrote `nonisolated` onto 678 declarations
# and Xcode's copy removed every one of them on the next build.
#
# Only `vtablePtr` needs patching. The rest of what this script used to do —
# `nonisolated` on every public function, the escaping-callback and
# continuation-map rewrites — was for a UniFFI version this project no longer
# uses, and had been dead for as long as Xcode was the last writer.
#
# Env:
#   CARGO_TARGET_DIR  where cargo builds (default: <repo>/target)
#   OUT_DIR           where the bindings land (default: <repo>/swift/generated)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FFI_DIR="${REPO_ROOT}/ffi"
BINDGEN_MANIFEST="${REPO_ROOT}/tools/uniffi-bindgen/Cargo.toml"
CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-${REPO_ROOT}/target}"
OUT_DIR="${OUT_DIR:-${REPO_ROOT}/swift/generated}"
PROFILE="${PROFILE:-debug}"
HOST_DYLIB="${CARGO_TARGET_DIR}/${PROFILE}/libspectra_core.dylib"
export CARGO_TARGET_DIR

export PATH="${HOME}/.cargo/bin:/opt/homebrew/bin:/usr/local/bin:${PATH}"
if [[ -f "${HOME}/.cargo/env" ]]; then source "${HOME}/.cargo/env"; fi

if ! command -v cargo >/dev/null 2>&1; then
  echo "error: cargo is required to build the Rust wallet core" >&2
  echo "hint: install Rust with 'brew install rustup-init && rustup-init' or from https://rustup.rs" >&2
  exit 1
fi

# `set -u` plus an empty array is an unbound-variable error on bash 3.2, which
# is what macOS ships and what an Xcode build phase runs.
RELEASE_FLAG=""
if [[ "${PROFILE}" == release ]]; then RELEASE_FLAG="--release"; fi

echo "Building ffi crate (host)..."
cargo build ${RELEASE_FLAG} --manifest-path "${FFI_DIR}/Cargo.toml"

mkdir -p "${OUT_DIR}"
echo "Generating Swift bindings..."
cargo run --manifest-path "${BINDGEN_MANIFEST}" \
  -- generate --language swift --library "${HOST_DYLIB}" --out-dir "${OUT_DIR}"

cp "${OUT_DIR}/spectra_coreFFI.modulemap" "${OUT_DIR}/module.modulemap"

# Swift 6: `vtablePtr` is an `UnsafePointer` static let, initialized once.
# Write the temp file OUTSIDE OUT_DIR so Xcode's synchronized root group cannot
# catch a transient `.!NNNN!` ghost.
PATCH_TMP="$(mktemp -t spectra_core.swift.XXXXXX)"
sed -e 's/    static let vtablePtr:/    nonisolated(unsafe) static let vtablePtr:/' \
  "${OUT_DIR}/spectra_core.swift" > "${PATCH_TMP}"
mv "${PATCH_TMP}" "${OUT_DIR}/spectra_core.swift"

echo "Swift bindings written to ${OUT_DIR}"
