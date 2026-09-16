#!/usr/bin/env bash
# Pin the deployment target the Rust core's C sources compile against.
#
# Source this — it exports into the caller's environment — with
# CARGO_TARGET_DIR already set:
#
#   export CARGO_TARGET_DIR=…
#   source "${REPO_ROOT}/scripts/ios-rust-build-env.sh"
#
# Two things go wrong without it.
#
# `cc` stamps every object it builds with IPHONEOS_DEPLOYMENT_TARGET, or with
# the installed SDK's version when that variable is unset. A command-line
# build therefore stamps the C half of `libspectra_core.a` with whatever SDK
# is on the machine, which the linker reports as "built for newer 'iOS'
# version (26.2) than being linked (26.0)". Xcode sets the variable itself, so
# take the app's own minimum from the project and use it everywhere else.
#
# The stamp then has to be able to change. `ring` 0.16.20 — reached through
# arti's `x509-signature` — has a build script that emits no
# `rerun-if-env-changed`, so cargo keeps its C objects across a change to the
# minimum iOS version and the same warning survives every rebuild. Only
# discarding them helps, so record the target and clear the cache when it
# moves.
set -euo pipefail

if [[ -z "${CARGO_TARGET_DIR:-}" ]]; then
  echo "ios-rust-build-env.sh: set CARGO_TARGET_DIR before sourcing" >&2
  exit 1
fi

_spectra_repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ -z "${IPHONEOS_DEPLOYMENT_TARGET:-}" ]]; then
  _spectra_pbxproj="${_spectra_repo_root}/swift/Spectra.xcodeproj/project.pbxproj"
  # One value or none: a project whose targets disagree has no single answer
  # to stamp objects with, and guessing the wrong one is the bug above.
  IPHONEOS_DEPLOYMENT_TARGET="$(
    sed -n 's/.*IPHONEOS_DEPLOYMENT_TARGET = \([0-9][0-9.]*\);.*/\1/p' \
      "${_spectra_pbxproj}" | sort -u
  )"
  if [[ "$(printf '%s' "${IPHONEOS_DEPLOYMENT_TARGET}" | grep -c .)" != "1" ]]; then
    echo "ios-rust-build-env.sh: expected exactly one IPHONEOS_DEPLOYMENT_TARGET in" \
      "${_spectra_pbxproj}, found: ${IPHONEOS_DEPLOYMENT_TARGET:-none}" >&2
    exit 1
  fi
fi
export IPHONEOS_DEPLOYMENT_TARGET

_spectra_stamp="${CARGO_TARGET_DIR}/.ios-deployment-target"
if [[ "$(cat "${_spectra_stamp}" 2>/dev/null || true)" != "${IPHONEOS_DEPLOYMENT_TARGET}" ]]; then
  # Only the iOS triples. `scripts/build-ios.sh` shares the workspace's
  # `target/`, whose host build is not stamped with a deployment target and
  # would be a long rebuild for nothing.
  for _spectra_triple in aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios; do
    rm -rf "${CARGO_TARGET_DIR:?}/${_spectra_triple}"
  done
  mkdir -p "${CARGO_TARGET_DIR}"
  printf '%s' "${IPHONEOS_DEPLOYMENT_TARGET}" >"${_spectra_stamp}"
fi

unset _spectra_repo_root _spectra_pbxproj _spectra_stamp _spectra_triple
