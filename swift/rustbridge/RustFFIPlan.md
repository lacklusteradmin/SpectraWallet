# Rust Bridge Plan (Current)

## Scope

Keep `Derivation/` as the app-facing API and run derivation core logic in Rust through the generated UniFFI bridge.

## Current Status

- `WalletDerivationEngine` derives via Rust bridge.
- Shared chain IDs are expanded for all currently supported `SeedDerivationChain` cases.
- Rust library is built and linked by Xcode build phase.
- UniFFI Swift bindings are generated during the Xcode build.
- Rust unit smoke test validates derivation output presence for all supported chains.

## Boundary Contract

- Runtime boundary is UniFFI-generated FFI with Swift bridge adapters.
- Complex request and response payloads are JSON encoded at the Swift adapter layer.
- Secret inputs stay on the Rust side as owned values once deserialized.

## Remaining Cleanup/Migration

1. Replace remaining `WalletCore`-backed material helpers with Rust-backed equivalents where still needed.
2. Remove Derivation-local `WalletCore` imports and update dependent send engines.
3. Keep parity checks for address/public/private key outputs per chain.
4. Keep generated bridge artifacts out of manual edits.

## Guardrails

- Do not change shared numeric IDs casually.
- Keep top-level ownership boundaries intact: `Derivation/`, `Fetch/`, `Send/`.
- Keep seed safety first: minimize exposure, avoid plaintext logging, and preserve Rust-side zeroization.
