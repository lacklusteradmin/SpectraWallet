# Derivation Testing Format

This bridge now uses UniFFI-generated Swift bindings with JSON payloads at the adapter layer.

## Entry Points

- Rust export: `derivation_derive_json(request_json: String) -> Result<String, SpectraBridgeError>`
- Rust export: `derivation_derive_from_private_key_json(request_json: String) -> Result<String, SpectraBridgeError>`
- Swift adapter:
  - `WalletRustDerivationBridge.derive(_:)`
  - `WalletRustDerivationBridge.deriveFromPrivateKey(chain:network:privateKeyHex:)`

## Request Payload

Seed-phrase derivation payload:

```json
{
  "chain": 0,
  "network": 0,
  "curve": 0,
  "requestedOutputs": 7,
  "derivationAlgorithm": 1,
  "addressAlgorithm": 1,
  "publicKeyFormat": 1,
  "scriptType": 3,
  "seedPhrase": "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about",
  "derivationPath": "m/84'/0'/0'/0/0",
  "passphrase": "",
  "hmacKey": null,
  "mnemonicWordlist": "english",
  "iterationCount": 2048
}
```

Private-key derivation payload:

```json
{
  "chain": 1,
  "network": 0,
  "curve": 0,
  "addressAlgorithm": 2,
  "publicKeyFormat": 1,
  "scriptType": 5,
  "privateKeyHex": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
}
```

## Response Payload

```json
{
  "address": "optional string",
  "publicKeyHex": "optional string",
  "privateKeyHex": "optional string"
}
```

## Shared IDs

These numeric values are still part of the Swift/Rust contract:

- `chain`: `0...21`
- `network`: `0...3`
- `curve`: `0...1`
- `requestedOutputs` bitmask:
  - `1 << 0`: address
  - `1 << 1`: public key
  - `1 << 2`: private key
- `derivationAlgorithm`: `0=auto`, `1=bip32_secp256k1`, `2=slip10_ed25519`
- `addressAlgorithm`: `0=auto`, `1=bitcoin`, `2=evm`, `3=solana`
- `publicKeyFormat`: `0=auto`, `1=compressed`, `2=uncompressed`, `3=x_only`, `4=raw`
- `scriptType`: `0=auto`, `1=p2pkh`, `2=p2sh_p2wpkh`, `3=p2wpkh`, `4=p2tr`, `5=account`

## Swift-Side Test Format

```swift
let request = try WalletRustDerivationBridge.makeRequestModel(
    chain: .bitcoin,
    network: .mainnet,
    seedPhrase: "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about",
    derivationPath: "m/84'/0'/0'/0/0",
    passphrase: "",
    iterationCount: 2048,
    hmacKeyString: nil,
    requestedOutputs: [.address, .publicKey, .privateKey]
)

let response = try WalletRustDerivationBridge.derive(request)
```

## Minimum Test Cases

1. Bitcoin mainnet p2wpkh.
2. Ethereum mainnet.
3. Solana mainnet.
4. One case for each remaining chain using its default curve and default path.
5. Negative tests:
   - wrong curve for chain
   - unsupported network for chain
   - empty seed phrase
   - `requestedOutputs = 0`

## Pass/Fail Criteria

- Success cases return non-empty requested outputs.
- Failure cases throw a bridge error with a non-empty message.
- No tests should rely on manual response freeing or raw C structs.
