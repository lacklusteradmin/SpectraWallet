import Foundation
import CryptoKit

enum UTXOAddressCodec {
    enum SegWitAddressEncoding {
        case bech32
        case bech32m
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

        let leadingZeroCount = string.prefix { $0 == "1" }.count
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

    static func base58CheckEncode(_ payload: Data) -> String {
        let checksum = Data(SHA256.hash(data: Data(SHA256.hash(data: payload))).prefix(4))
        let full = payload + checksum
        let alphabet = Array("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")
        var bytes = [UInt8](full)
        var encoded = ""

        while !bytes.isEmpty && bytes.contains(where: { $0 != 0 }) {
            var quotient: [UInt8] = []
            var remainder = 0

            for byte in bytes {
                let accumulator = Int(byte) + (remainder << 8)
                let digit = accumulator / 58
                remainder = accumulator % 58
                if !quotient.isEmpty || digit != 0 {
                    quotient.append(UInt8(digit))
                }
            }

            encoded.append(alphabet[remainder])
            bytes = quotient
        }

        for byte in full where byte == 0 {
            encoded.append("1")
        }

        return String(encoded.reversed())
    }

    static func hash160(_ data: Data) -> Data {
        RIPEMD160.hash(data: Data(SHA256.hash(data: data)))
    }

    static func legacyScriptPubKey(
        for address: String,
        p2pkhVersions: Set<UInt8>,
        p2shVersions: Set<UInt8>
    ) -> Data? {
        guard let decoded = base58CheckDecode(address), !decoded.isEmpty else {
            return nil
        }

        let prefix = decoded[0]
        let hash160 = decoded.dropFirst()
        guard hash160.count == 20 else { return nil }

        if p2pkhVersions.contains(prefix) {
            return Data([0x76, 0xa9, 0x14]) + hash160 + Data([0x88, 0xac])
        }
        if p2shVersions.contains(prefix) {
            return Data([0xa9, 0x14]) + hash160 + Data([0x87])
        }
        return nil
    }

    static func legacyP2PKHAddress(
        privateKeyData: Data,
        version: UInt8
    ) throws -> String {
        let publicKey = try compressedSecp256k1PublicKey(privateKeyData: privateKeyData)
        let payload = Data([version]) + hash160(publicKey)
        return base58CheckEncode(payload)
    }

    static func nestedSegWitP2SHAddress(
        privateKeyData: Data,
        scriptVersion: UInt8
    ) throws -> String {
        let publicKey = try compressedSecp256k1PublicKey(privateKeyData: privateKeyData)
        let witnessProgram = hash160(publicKey)
        let redeemScript = Data([0x00, 0x14]) + witnessProgram
        let payload = Data([scriptVersion]) + hash160(redeemScript)
        return base58CheckEncode(payload)
    }

    static func segWitAddress(
        privateKeyData: Data,
        hrp: String,
        witnessVersion: UInt8 = 0,
        encoding: SegWitAddressEncoding = .bech32
    ) throws -> String {
        let compressedPublicKey = try compressedSecp256k1PublicKey(privateKeyData: privateKeyData)
        let program: Data
        switch witnessVersion {
        case 0:
            program = hash160(compressedPublicKey)
        case 1:
            guard compressedPublicKey.count == 33 else {
                throw UTXOAddressCodecError.unsupportedWitnessVersion
            }
            program = compressedPublicKey.dropFirst()
        default:
            throw UTXOAddressCodecError.unsupportedWitnessVersion
        }

        guard let convertedProgram = convertBits(
            Array(program),
            fromBits: 8,
            toBits: 5,
            pad: true
        ) else {
            throw UTXOAddressCodecError.invalidWitnessProgram
        }

        let data = [witnessVersion] + convertedProgram
        return try bech32Encode(
            hrp: hrp.lowercased(),
            data: data,
            encoding: encoding
        )
    }

    private static func bech32Encode(
        hrp: String,
        data: [UInt8],
        encoding: SegWitAddressEncoding
    ) throws -> String {
        let alphabet = Array("qpzry9x8gf2tvdw0s3jn54khce6mua7l")
        let checksum = createBech32Checksum(hrp: hrp, data: data, encoding: encoding)
        let combined = data + checksum
        guard combined.allSatisfy({ Int($0) < alphabet.count }) else {
            throw UTXOAddressCodecError.invalidWitnessProgram
        }
        let payload = combined.map { String(alphabet[Int($0)]) }.joined()
        return "\(hrp)1\(payload)"
    }

    private static func createBech32Checksum(
        hrp: String,
        data: [UInt8],
        encoding: SegWitAddressEncoding
    ) -> [UInt8] {
        let polymodInput = expandBech32Hrp(hrp) + data + Array(repeating: 0, count: 6)
        let constant: UInt32 = {
            switch encoding {
            case .bech32:
                return 1
            case .bech32m:
                return 0x2bc830a3
            }
        }()
        let polymod = bech32Polymod(polymodInput) ^ constant
        return (0..<6).map { index in
            UInt8((polymod >> (5 * (5 - index))) & 31)
        }
    }

    private static func expandBech32Hrp(_ hrp: String) -> [UInt8] {
        let scalarValues = hrp.unicodeScalars.map(\.value)
        return scalarValues.map { UInt8($0 >> 5) } + [0] + scalarValues.map { UInt8($0 & 31) }
    }

    private static func bech32Polymod(_ values: [UInt8]) -> UInt32 {
        let generators: [UInt32] = [
            0x3b6a57b2,
            0x26508e6d,
            0x1ea119fa,
            0x3d4233dd,
            0x2a1462b3
        ]

        var checksum: UInt32 = 1
        for value in values {
            let top = checksum >> 25
            checksum = (checksum & 0x1ffffff) << 5 ^ UInt32(value)
            for (index, generator) in generators.enumerated() where ((top >> index) & 1) != 0 {
                checksum ^= generator
            }
        }
        return checksum
    }

    private static func convertBits(
        _ data: [UInt8],
        fromBits: Int,
        toBits: Int,
        pad: Bool
    ) -> [UInt8]? {
        var accumulator = 0
        var bits = 0
        let maxValue = (1 << toBits) - 1
        var result: [UInt8] = []

        for value in data {
            guard (Int(value) >> fromBits) == 0 else { return nil }
            accumulator = (accumulator << fromBits) | Int(value)
            bits += fromBits
            while bits >= toBits {
                bits -= toBits
                result.append(UInt8((accumulator >> bits) & maxValue))
            }
        }

        if pad {
            if bits > 0 {
                result.append(UInt8((accumulator << (toBits - bits)) & maxValue))
            }
        } else if bits >= fromBits || ((accumulator << (toBits - bits)) & maxValue) != 0 {
            return nil
        }

        return result
    }

    private static func compressedSecp256k1PublicKey(privateKeyData: Data) throws -> Data {
        guard privateKeyData.count == 32 else {
            throw UTXOAddressCodecError.invalidPrivateKey
        }
        let privateKeyHex = privateKeyData.map { String(format: "%02x", $0) }.joined()
        let response = try WalletRustDerivationBridge.deriveFromPrivateKey(
            chain: .bitcoin,
            network: .mainnet,
            privateKeyHex: privateKeyHex
        )
        guard let publicKeyHex = response.publicKeyHex,
              let publicKeyData = Data(hexEncoded: publicKeyHex),
              publicKeyData.count == 33 else {
            throw UTXOAddressCodecError.invalidPrivateKey
        }
        return publicKeyData
    }
}

enum UTXOAddressCodecError: Error {
    case invalidPrivateKey
    case invalidWitnessProgram
    case unsupportedWitnessVersion
}

private enum RIPEMD160 {
    private static let initialState: [UInt32] = [
        0x67452301,
        0xefcdab89,
        0x98badcfe,
        0x10325476,
        0xc3d2e1f0
    ]

    private static let leftShifts: [UInt32] = [
        11, 14, 15, 12, 5, 8, 7, 9, 11, 13, 14, 15, 6, 7, 9, 8,
        7, 6, 8, 13, 11, 9, 7, 15, 7, 12, 15, 9, 11, 7, 13, 12,
        11, 13, 6, 7, 14, 9, 13, 15, 14, 8, 13, 6, 5, 12, 7, 5,
        11, 12, 14, 15, 14, 15, 9, 8, 9, 14, 5, 6, 8, 6, 5, 12,
        9, 15, 5, 11, 6, 8, 13, 12, 5, 12, 13, 14, 11, 8, 5, 6
    ]

    private static let rightShifts: [UInt32] = [
        8, 9, 9, 11, 13, 15, 15, 5, 7, 7, 8, 11, 14, 14, 12, 6,
        9, 13, 15, 7, 12, 8, 9, 11, 7, 7, 12, 7, 6, 15, 13, 11,
        9, 7, 15, 11, 8, 6, 6, 14, 12, 13, 5, 14, 13, 13, 7, 5,
        15, 5, 8, 11, 14, 14, 6, 14, 6, 9, 12, 9, 12, 5, 15, 8,
        8, 5, 12, 9, 12, 5, 14, 6, 8, 13, 6, 5, 15, 13, 11, 11
    ]

    private static let leftIndexes: [Int] = [
        0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
        7, 4, 13, 1, 10, 6, 15, 3, 12, 0, 9, 5, 2, 14, 11, 8,
        3, 10, 14, 4, 9, 15, 8, 1, 2, 7, 0, 6, 13, 11, 5, 12,
        1, 9, 11, 10, 0, 8, 12, 4, 13, 3, 7, 15, 14, 5, 6, 2,
        4, 0, 5, 9, 7, 12, 2, 10, 14, 1, 3, 8, 11, 6, 15, 13
    ]

    private static let rightIndexes: [Int] = [
        5, 14, 7, 0, 9, 2, 11, 4, 13, 6, 15, 8, 1, 10, 3, 12,
        6, 11, 3, 7, 0, 13, 5, 10, 14, 15, 8, 12, 4, 9, 1, 2,
        15, 5, 1, 3, 7, 14, 6, 9, 11, 8, 12, 2, 10, 0, 4, 13,
        8, 6, 4, 1, 3, 11, 15, 0, 5, 12, 2, 13, 9, 7, 10, 14,
        12, 15, 10, 4, 1, 5, 8, 7, 6, 2, 13, 14, 0, 3, 9, 11
    ]

    static func hash(data: Data) -> Data {
        var state = initialState
        let paddedData = pad(data)

        for chunkOffset in stride(from: 0, to: paddedData.count, by: 64) {
            let chunk = paddedData[chunkOffset ..< chunkOffset + 64]
            let words = chunk.withUnsafeBytes { rawBuffer -> [UInt32] in
                (0 ..< 16).map { index in
                    let start = rawBuffer.baseAddress!.advanced(by: index * 4)
                    return start.assumingMemoryBound(to: UInt32.self).pointee.littleEndian
                }
            }

            var left = state
            var right = state

            for step in 0 ..< 80 {
                let leftTemp = left[0]
                    &+ f(step, left[1], left[2], left[3])
                    &+ words[leftIndexes[step]]
                    &+ k(step)
                let newLeft1 = leftTemp.rotateLeft(by: leftShifts[step]) &+ left[4]
                left[0] = left[4]
                left[4] = left[3]
                left[3] = left[2].rotateLeft(by: 10)
                left[2] = left[1]
                left[1] = newLeft1

                let rightTemp = right[0]
                    &+ parallelF(step, right[1], right[2], right[3])
                    &+ words[rightIndexes[step]]
                    &+ parallelK(step)
                let newRight1 = rightTemp.rotateLeft(by: rightShifts[step]) &+ right[4]
                right[0] = right[4]
                right[4] = right[3]
                right[3] = right[2].rotateLeft(by: 10)
                right[2] = right[1]
                right[1] = newRight1
            }

            let combined = state[1] &+ left[2] &+ right[3]
            state[1] = state[2] &+ left[3] &+ right[4]
            state[2] = state[3] &+ left[4] &+ right[0]
            state[3] = state[4] &+ left[0] &+ right[1]
            state[4] = state[0] &+ left[1] &+ right[2]
            state[0] = combined
        }

        var digest = Data(capacity: 20)
        for word in state {
            var littleEndian = word.littleEndian
            withUnsafeBytes(of: &littleEndian) { digest.append(contentsOf: $0) }
        }
        return digest
    }

    private static func pad(_ data: Data) -> Data {
        var padded = data
        let bitLength = UInt64(data.count) * 8
        padded.append(0x80)
        while padded.count % 64 != 56 {
            padded.append(0)
        }
        var littleEndianLength = bitLength.littleEndian
        withUnsafeBytes(of: &littleEndianLength) { padded.append(contentsOf: $0) }
        return padded
    }

    private static func f(_ step: Int, _ x: UInt32, _ y: UInt32, _ z: UInt32) -> UInt32 {
        switch step {
        case 0 ..< 16:
            return x ^ y ^ z
        case 16 ..< 32:
            return (x & y) | (~x & z)
        case 32 ..< 48:
            return (x | ~y) ^ z
        case 48 ..< 64:
            return (x & z) | (y & ~z)
        default:
            return x ^ (y | ~z)
        }
    }

    private static func parallelF(_ step: Int, _ x: UInt32, _ y: UInt32, _ z: UInt32) -> UInt32 {
        switch step {
        case 0 ..< 16:
            return x ^ (y | ~z)
        case 16 ..< 32:
            return (x & z) | (y & ~z)
        case 32 ..< 48:
            return (x | ~y) ^ z
        case 48 ..< 64:
            return (x & y) | (~x & z)
        default:
            return x ^ y ^ z
        }
    }

    private static func k(_ step: Int) -> UInt32 {
        switch step {
        case 0 ..< 16:
            return 0x00000000
        case 16 ..< 32:
            return 0x5a827999
        case 32 ..< 48:
            return 0x6ed9eba1
        case 48 ..< 64:
            return 0x8f1bbcdc
        default:
            return 0xa953fd4e
        }
    }

    private static func parallelK(_ step: Int) -> UInt32 {
        switch step {
        case 0 ..< 16:
            return 0x50a28be6
        case 16 ..< 32:
            return 0x5c4dd124
        case 32 ..< 48:
            return 0x6d703ef3
        case 48 ..< 64:
            return 0x7a6d76e9
        default:
            return 0x00000000
        }
    }
}

private extension UInt32 {
    func rotateLeft(by amount: UInt32) -> UInt32 {
        (self << amount) | (self >> (32 - amount))
    }
}
