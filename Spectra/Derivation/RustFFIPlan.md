# Rust FFI Plan (Current)

## Scope

Keep `Derivation/` as the app-facing API and run derivation core logic in Rust through the FFI bridge.

## Current Status

- `WalletDerivationEngine` derives via Rust bridge.
- FFI chain IDs are expanded for all currently supported `SeedDerivationChain` cases.
- Rust library is built and linked by Xcode build phase.
- Rust unit smoke test validates derivation output presence for all supported chains.

## Boundary Contract

- Runtime boundary is raw FFI (`spectra_derivation_derive`, `spectra_derivation_response_free`).
- Request/response structs are defined in:
  - `Spectra/Derivation/Rust/include/spectra_derivation.h`
- Secret inputs are passed as UTF-8 buffers and zeroized on Swift side after call.

## Remaining Cleanup/Migration

1. Replace `Derivation/SeedPhrase/*` WalletCore-backed material helpers with Rust-backed equivalents.
2. Remove `Derivation/WalletCore/WalletCoreDerivationSupport.swift` once no callers remain.
3. Remove Derivation-local `WalletCore` imports and update dependent send engines.
4. Keep parity checks for address/public/private key outputs per chain.

## Guardrails

- Do not change numeric FFI IDs casually.
- Keep top-level ownership boundaries intact: `Derivation/`, `Fetch/`, `Send/`.
- Keep seed safety first: minimize exposure, zeroize buffers, avoid plaintext logging.
