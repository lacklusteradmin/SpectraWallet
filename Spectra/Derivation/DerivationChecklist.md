# Derivation Checklist

## Purpose

For one seed phrase and one fully specified derivation process, produce the one correct:

- `address`
- `public key`
- `private key`

This checklist is about the inputs that define that process.

## Stage 1: Mnemonic -> Seed

**Must know**

- Mnemonic scheme
  - BIP-39
  - non-BIP-39
- Language / wordlist
  - English
  - other supported wordlists
- Normalization rule
  - whitespace
  - Unicode
  - checksum validation
- Passphrase
  - empty
  - custom
- Salt construction rule
  - standard BIP-39 salt
  - custom salt
- Iteration count
  - default
  - custom
- PRF / HMAC function
  - `HMAC-SHA512`
  - other supported function

**Output**

- Seed bytes

## Stage 2: Seed -> Master Key

**Must know**

- Seed-to-master-key algorithm
  - BIP-32 style
  - SLIP-0010 style
  - chain-specific
- Master HMAC key string
  - standard
  - custom
- Derivation family
  - BIP-32
  - SLIP-0010
  - ed25519 HD variant
  - chain-specific

**Output**

- Master private key
- Master chain code or equivalent state

## Stage 3: Master Key -> Child Key

**Must know**

- Derivation path
  - root only
  - full explicit path
  - partial path with defaults
- Path interpretation rule
  - standard BIP-32 meaning
  - curve-specific meaning
  - chain-specific meaning
- Path components
  - purpose
  - coin type
  - account
  - branch / change
  - index
- Hardened semantics
  - hardened allowed
  - non-hardened allowed
  - hardened-only family
- Curve family
  - `secp256k1`
  - `secp256r1`
  - `ed25519`
  - other supported curves
- Curve variant
  - plain
  - HD variant
  - chain-specific variant

**Output**

- Final child private key material

## Stage 4: Private Key -> Public Key

**Must know**

- Public key derivation rule
  - secp rule
  - ed25519 rule
  - chain-specific rule
- Public key format
  - compressed
  - uncompressed
  - x-only
  - raw bytes
  - chain-specific wrapped format

**Output**

- Public key bytes in the correct format

## Stage 5: Key Material -> Address

**Must know**

- Address generation algorithm
  - UTXO rule
  - EVM rule
  - Solana-style rule
  - Stellar-style rule
  - XRP-style rule
  - chain-specific rule
- Script / output type
  - legacy
  - nested segwit
  - native segwit
  - taproot
  - account-style
  - chain-specific type
- Address encoding scheme
  - `base58`
  - `base58check`
  - `bech32`
  - `bech32m`
  - `hex`
  - `SS58`
  - `StrKey`
  - chain-specific encoding
- Network constants
  - HRP
  - version bytes
  - checksum variant
  - chain / network prefix

**Output**

- Final address string

## Global Inputs

**Must know**

- Chain
- Network
- Preset / default resolution
- Invalid combination rules
  - curve invalid for derivation family
  - path invalid for derivation family
  - address type invalid for chain
  - network invalid for chain

## Requested Outputs

- `address`
- `public key`
- `private key`
- optional future outputs
  - `xpub` / `xprv`
  - `ypub` / `yprv`
  - `zpub` / `zprv`

## Correctness Formula

The right result requires:

- complete inputs
- correct chain implementation
- valid combination
- verified test vectors

## Security Rules

- never log the seed phrase
- never log the private key
- minimize secret copies
- zero sensitive buffers where possible
- if moving to Rust FFI, keep runtime secret transport binary, not text
