import Foundation
import CryptoKit

extension DogecoinWalletEngine {
    static func standardScriptPubKey(for address: String) -> Data? {
        guard let decoded = base58CheckDecode(address), !decoded.isEmpty else {
            return nil
        }

        let prefix = decoded[0]
        let hash160 = decoded.dropFirst()
        guard hash160.count == 20 else { return nil }

        switch prefix {
        case 0x1e, 0x71:
            return Data([0x76, 0xa9, 0x14]) + hash160 + Data([0x88, 0xac])
        case 0x16, 0xc4:
            return Data([0xa9, 0x14]) + hash160 + Data([0x87])
        default:
            return nil
        }
    }

    static func base58CheckDecode(_ string: String) -> Data? {
        let alphabet = Array("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")
        var indexes: [Character: Int] = [:]
        for (index, character) in alphabet.enumerated() {
            indexes[character] = index
        }

        var bytes: [UInt8] = [0]
        for character in string {
            guard let value = indexes[character] else { return nil }
            var carry = value
            for idx in bytes.indices {
                let x = Int(bytes[idx]) * 58 + carry
                bytes[idx] = UInt8(x & 0xff)
                carry = x >> 8
            }
            while carry > 0 {
                bytes.append(UInt8(carry & 0xff))
                carry >>= 8
            }
        }

        var leadingZeroCount = 0
        for character in string where character == "1" {
            leadingZeroCount += 1
        }

        let decoded = Data(repeating: 0, count: leadingZeroCount) + Data(bytes.reversed())
        guard decoded.count >= 5 else { return nil }

        let payload = decoded.dropLast(4)
        let checksum = decoded.suffix(4)
        let firstHash = SHA256.hash(data: payload)
        let secondHash = SHA256.hash(data: Data(firstHash))
        let computedChecksum = Data(secondHash.prefix(4))
        guard checksum.elementsEqual(computedChecksum) else { return nil }

        return Data(payload)
    }

    static func base58CheckEncode(_ payload: Data) -> String? {
        guard !payload.isEmpty else { return nil }

        let checksum = Data(SHA256.hash(data: Data(SHA256.hash(data: payload))).prefix(4))
        let bytes = [UInt8](payload + checksum)
        let alphabet = Array("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")

        var digits = [UInt8](repeating: 0, count: 1)
        for byte in bytes {
            var carry = Int(byte)
            for index in digits.indices {
                let total = (Int(digits[index]) << 8) + carry
                digits[index] = UInt8(total % 58)
                carry = total / 58
            }
            while carry > 0 {
                digits.append(UInt8(carry % 58))
                carry /= 58
            }
        }

        var result = String(repeating: "1", count: bytes.prefix { $0 == 0 }.count)
        for digit in digits.reversed() {
            result.append(alphabet[Int(digit)])
        }
        return result
    }

    static func normalizeAddressForCurrentNetwork(_ address: String) -> String? {
        guard networkMode == .testnet,
              let payload = base58CheckDecode(address),
              let version = payload.first else {
            return address
        }
        let adjustedVersion: UInt8
        switch version {
        case 0x1e:
            adjustedVersion = 0x71
        case 0x16:
            adjustedVersion = 0xc4
        case 0x71, 0xc4:
            adjustedVersion = version
        default:
            return address
        }
        return reencodedAddress(payload: payload, version: adjustedVersion)
    }

    static func walletCoreCompatibleAddress(_ address: String) -> String {
        guard networkMode == .testnet,
              let payload = base58CheckDecode(address),
              let version = payload.first else {
            return address
        }
        let adjustedVersion: UInt8
        switch version {
        case 0x71:
            adjustedVersion = 0x1e
        case 0xc4:
            adjustedVersion = 0x16
        default:
            adjustedVersion = version
        }
        return reencodedAddress(payload: payload, version: adjustedVersion) ?? address
    }

    static func reencodedAddress(payload: Data, version: UInt8) -> String? {
        guard payload.count >= 2 else { return nil }
        var adjustedPayload = payload
        adjustedPayload[adjustedPayload.startIndex] = version
        return base58CheckEncode(adjustedPayload)
    }

    static func computeTXID(fromRawHex rawHex: String) -> String {
        guard let rawData = Data(hexEncoded: rawHex) else {
            return ""
        }
        let firstHash = SHA256.hash(data: rawData)
        let secondHash = SHA256.hash(data: Data(firstHash))
        return Data(secondHash.reversed()).map { String(format: "%02x", $0) }.joined()
    }
}
