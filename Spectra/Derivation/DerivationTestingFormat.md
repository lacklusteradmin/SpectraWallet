# Derivation Testing Format (FFI Boundary)

This is the non-JSON derivation test contract.
Current runtime bridge uses C-ABI symbols (`spectra_derivation_derive`, `spectra_derivation_response_free`) from Rust and Swift bridge types.

## Entry Point

- Rust symbol: `spectra_derivation_derive(const SpectraDerivationRequest*) -> SpectraDerivationResponse*`
- Rust free: `spectra_derivation_response_free(SpectraDerivationResponse*)`

Header source:
- [spectra_derivation.h](/Users/sheny6n/Spectra/Spectra/Derivation/Rust/include/spectra_derivation.h)

## Request Struct

```c
typedef struct SpectraDerivationRequest {
    uint32_t chain;
    uint32_t network;
    uint32_t curve;
    uint32_t requested_outputs;
    uint32_t derivation_algorithm;
    uint32_t address_algorithm;
    uint32_t public_key_format;
    uint32_t script_type;
    SpectraBuffer seed_phrase_utf8;
    SpectraBuffer derivation_path_utf8;
    SpectraBuffer passphrase_utf8;
    SpectraBuffer hmac_key_utf8;
    SpectraBuffer mnemonic_wordlist_utf8;
    uint32_t iteration_count;
} SpectraDerivationRequest;
```

`SpectraBuffer`:

```c
typedef struct SpectraBuffer {
    uint8_t *ptr;
    size_t len;
} SpectraBuffer;
```

All text fields are UTF-8 bytes (not null-terminated strings).

## Response Struct

```c
typedef struct SpectraDerivationResponse {
    int32_t status_code; // 0 = success, 1 = error
    SpectraBuffer address_utf8;
    SpectraBuffer public_key_hex_utf8;
    SpectraBuffer private_key_hex_utf8;
    SpectraBuffer error_message_utf8;
} SpectraDerivationResponse;
```

## Enum/Flag IDs

Use IDs exactly as frozen in `spectra_derivation.h`.

- `chain`: `0...21`
- `network`: `0...3`
- `curve`: `0...1`
- `requested_outputs` bitmask:
  - `1 << 0`: address
  - `1 << 1`: public key
  - `1 << 2`: private key

Common algorithm IDs:
- `derivation_algorithm`: `0=auto`, `1=bip32_secp256k1`, `2=slip10_ed25519`
- `address_algorithm`: `0=auto`, `1=bitcoin`, `2=evm`, `3=solana`
- `public_key_format`: `0=auto`, `1=compressed`, `2=uncompressed`, `3=x_only`, `4=raw`
- `script_type`: `0=auto`, `1=p2pkh`, `2=p2sh_p2wpkh`, `3=p2wpkh`, `4=p2tr`, `5=account`

## Required Safety Rules for Tests

- Always zeroize seed/passphrase/hmac buffers after call.
- Always call `spectra_derivation_response_free(response)` for non-null response.
- Never log seed phrase/passphrase/private key in plaintext.

## Swift-Side Test Format

Use `WalletRustDerivationRequestModel` (non-JSON).

```swift
let request = WalletRustDerivationRequestModel(
    chain: .bitcoin,
    network: .mainnet,
    curve: .secp256k1,
    requestedOutputs: [.address, .publicKey, .privateKey],
    derivationAlgorithm: .bip32Secp256k1,
    addressAlgorithm: .bitcoin,
    publicKeyFormat: .compressed,
    scriptType: .p2wpkh,
    seedPhrase: "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about",
    derivationPath: "m/84'/0'/0'/0/0",
    passphrase: "",
    hmacKey: "",
    mnemonicWordlist: "english",
    iterationCount: 2048
)

let response = try WalletRustDerivationBridge.derive(request)
```

## Minimum FFI Test Cases

1. Bitcoin mainnet p2wpkh (`chain=0`, `curve=0`, path `m/84'/0'/0'/0/0`)
2. Ethereum mainnet (`chain=1`, `curve=0`, path `m/44'/60'/0'/0/0`)
3. Solana mainnet (`chain=2`, `curve=1`, path `m/44'/501'/0'/0'`)
4. One case for each remaining chain ID `3...21` using its default curve and default path
5. Negative tests:
   - wrong curve for chain
   - unsupported network for chain
   - empty seed phrase
   - `requested_outputs = 0`

## Pass/Fail Criteria

- `status_code == 0` for valid vectors.
- Requested outputs are non-empty UTF-8.
- `status_code == 1` and non-empty `error_message_utf8` for invalid vectors.
