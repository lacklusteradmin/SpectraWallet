# Derivation Testing Format

The bridge uses UniFFI-generated typed Swift records. No JSON payloads cross the adapter layer.

## Entry Points

UniFFI-generated free functions (from `spectra_coreFFI`):

- `derivationDerive(request: UniFfiDerivationRequest) -> UniFfiDerivationResponse`
- `derivationDeriveFromPrivateKey(request: UniFfiPrivateKeyDerivationRequest) -> UniFfiDerivationResponse`
- `derivationBuildMaterial(request: UniFfiMaterialRequest) -> UniFfiSigningMaterial`
- `derivationBuildMaterialFromPrivateKey(request: UniFfiPrivateKeyMaterialRequest) -> UniFfiSigningMaterial`
- `derivationDeriveAllAddresses(seedPhrase: String, chainPaths: [String: String]) -> [String: String]`

Swift adapter (`WalletRustDerivationBridge`):

- `makeRequestModel(chain:network:seedPhrase:derivationPath:passphrase:iterationCount:hmacKeyString:requestedOutputs:)`
- `derive(_:)`
- `deriveFromPrivateKey(chain:network:privateKeyHex:)`
- `buildSigningMaterial(_:)`
- `buildSigningMaterialFromPrivateKey(chain:network:privateKeyHex:derivationPath:)`
- `deriveAllAddresses(seedPhrase:chainPaths:)`

The adapter passes `chain: nil` on every call — chain selection happens Swift-side via `WalletDerivationPresetCatalog`, and the Rust core infers behavior from the explicit `derivationAlgorithm`, `addressAlgorithm`, `publicKeyFormat`, and `scriptType` wire values.

## Wire Values

All enums are transported as `UInt32`. See `rustWireValue` extensions in `WalletRustDerivationBridge.swift`:

- `network`: `mainnet=0`, `testnet=1`, `testnet4=2`, `signet=3`
- `curve`: `secp256k1=0`, `ed25519=1`
- `requestedOutputs` bitmask: `address=1<<0`, `publicKey=1<<1`, `privateKey=1<<2`
- `derivationAlgorithm`: `bip32Secp256k1=1`, `slip10Ed25519=2`
- `addressAlgorithm`: `bitcoin=1`, `evm=2`, `solana=3`
- `publicKeyFormat`: `compressed=1`, `uncompressed=2`, `xOnly=3`, `raw=4`
- `scriptType`: `p2pkh=1`, `p2shP2wpkh=2`, `p2wpkh=3`, `p2tr=4`, `account=5`

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
4. One case per remaining chain using its default curve and default path.
5. Negative tests:
   - wrong curve for chain
   - unsupported network for chain
   - empty seed phrase
   - `requestedOutputs = 0`

## Pass/Fail Criteria

- Success cases return non-empty requested outputs on the typed response record.
- Failure cases throw a `SpectraBridgeError` surfaced as a Swift error with a non-empty message.
- No tests touch raw C structs or manual response freeing — UniFFI owns the memory boundary.
