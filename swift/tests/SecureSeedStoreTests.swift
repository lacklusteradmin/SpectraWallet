import Foundation
import Security
import Testing
@testable import Spectra

/// These read and write the real Keychain, and share its seed master key.
@Suite(.serialized)
struct SecureSeedStoreTests {
    /// The Keychain item as stored, read beside the store rather than through it.
    private func storedBytes(service: String, account: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecAttrAccount as String: account, kSecReturnData as String: true,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
        return result as? Data
    }
    @Test func loadMissingSeedThrows() {
        let account = "test.seed.missing.\(UUID().uuidString)"
        try? SealedSigningStore.seeds.deleteValue(for: account)
        #expect(throws: (any Error).self) { try SealedSigningStore.seeds.loadValue(for: account) }
    }
    // Writes use `try`, not `try?`: a store that fails to write must fail the
    // test rather than let the assertions below pass on stale or absent data.
    @Test func saveThenLoadRoundTripsSeed() throws {
        let account = "test.seed.roundtrip.\(UUID().uuidString)"
        let seed = "abandon ability able about above absent absorb abstract absurd abuse access accident"
        try SealedSigningStore.seeds.save(seed, for: account)
        defer { try? SealedSigningStore.seeds.deleteValue(for: account) }
        #expect(try SealedSigningStore.seeds.loadValue(for: account) == seed)
    }
    @Test func seedStorageDoesNotPersistPlaintextUTF8Payload() throws {
        let account = "test.seed.encrypted.\(UUID().uuidString)"
        let seed = "abandon ability able about above absent absorb abstract absurd abuse access accident"
        try SealedSigningStore.seeds.save(seed, for: account)
        defer { try? SealedSigningStore.seeds.deleteValue(for: account) }
        let storedData = try #require(try storedBytes(service: "com.spectra.seed", account: account))
        #expect(storedData != Data(seed.utf8))
        #expect(String(data: storedData, encoding: .utf8) != seed)
        // A plaintext fallback would put every seed word in the stored bytes.
        // Assert on the words themselves, not just on inequality with the exact
        // UTF-8 payload, so a partial downgrade cannot pass either.
        for word in seed.split(separator: " ") {
            #expect(storedData.range(of: Data(word.utf8)) == nil, "seed word \(word) appears in stored bytes")
        }
    }
    @Test func privateKeySaveThenLoadRoundTrips() throws {
        let account = "test.privatekey.roundtrip.\(UUID().uuidString)"
        let key = String(repeating: "ab", count: 32)
        try SealedSigningStore.privateKeys.save(key, for: account)
        defer { try? SealedSigningStore.privateKeys.deleteValue(for: account) }
        #expect(try SealedSigningStore.privateKeys.loadValue(for: account) == key)
    }
    /// A private key signs exactly as a seed does, so it is sealed the same way
    /// rather than written as the string that was pasted.
    @Test func privateKeyStorageDoesNotPersistPlaintext() throws {
        let account = "test.privatekey.encrypted.\(UUID().uuidString)"
        let key = "4c0883a69102937d6231471b5dbb6204fe5129617082792ae468d01a3f362318"
        try SealedSigningStore.privateKeys.save(key, for: account)
        defer { try? SealedSigningStore.privateKeys.deleteValue(for: account) }
        let storedData = try #require(try storedBytes(service: "com.spectra.privatekey", account: account))
        #expect(storedData.range(of: Data(key.utf8)) == nil, "the key is stored in the clear")
        #expect(storedData.range(of: Data(key.prefix(16).utf8)) == nil, "part of the key is stored in the clear")
    }
    /// A missing key is `missingValue`, which the adapter reports to core as
    /// not found. Anything else a read throws is a failure, not an absence.
    @Test func missingPrivateKeyReportsMissing() {
        let account = "test.privatekey.missing.\(UUID().uuidString)"
        try? SealedSigningStore.privateKeys.deleteValue(for: account)
        #expect(throws: KeychainStoreError.missingValue) {
            try SealedSigningStore.privateKeys.loadValue(for: account)
        }
        #expect(throws: SecretStoreError.NotFound, "a missing key must reach core as not found") {
            try SpectraSecretStoreAdapter().loadSecret(kind: .privateKey, key: account)
        }
    }
    @Test func deletedSeedIsNotReadableAndReportsMissing() throws {
        let account = "test.seed.deleted.\(UUID().uuidString)"
        try SealedSigningStore.seeds.save("abandon abandon abandon abandon abandon about", for: account)
        try SealedSigningStore.seeds.deleteValue(for: account)
        #expect(try storedBytes(service: "com.spectra.seed", account: account) == nil)
        #expect(throws: KeychainStoreError.missingValue) {
            try SealedSigningStore.seeds.loadValue(for: account)
        }
    }

    /// The master key reaches the Keychain only encrypted to the wrapping key
    /// — an ECIES blob (ephemeral point, ciphertext, tag), never the raw key.
    @Test func theMasterKeyIsStoredOnlyWrapped() throws {
        let account = "test.seed.wrapped.\(UUID().uuidString)"
        try SealedSigningStore.seeds.save("abandon ability able about above absent absorb abstract absurd abuse access accident", for: account)
        defer { try? SealedSigningStore.seeds.deleteValue(for: account) }
        let wrapped = try #require(try storedBytes(service: "com.spectra.seed.masterkey", account: "seed.material.masterkey.wrapped"))
        #expect(wrapped.first == 0x04, "an uncompressed ephemeral P-256 point leads the blob")
        #expect(wrapped.count > 65 + 16, "a raw master key is shorter than a wrapped one")
        let keyQuery: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: Data("com.spectra.seed.masterkey.wrapping".utf8),
        ]
        #expect(SecItemCopyMatching(keyQuery as CFDictionary, nil) == errSecSuccess, "the wrapping key is a Keychain key, not data")
    }

    /// Core's generic secrets live under the wallet service, not a leftover name.
    @Test func genericSecretsUseTheWalletService() throws {
        let account = "test.generic.service.\(UUID().uuidString)"
        try SpectraSecretStoreAdapter().saveSecret(kind: .generic, key: account, value: "v")
        defer { try? SpectraSecretStoreAdapter().deleteSecret(kind: .generic, key: account) }
        #expect(try storedBytes(service: "com.spectra.wallet", account: account) == Data("v".utf8))
        #expect(try storedBytes(service: "com.spectra.pricing", account: account) == nil)
    }
}
