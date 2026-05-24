import Foundation

/// QUIC variable-length integer encoding (RFC 9000 §16).
///
/// Encodes integers 0–4611686018427387903 using 1, 2, 4, or 8 bytes.
/// The two most-significant bits of the first byte encode the byte count:
///   00 → 1 byte  (max 63)
///   01 → 2 bytes (max 16383)
///   10 → 4 bytes (max 1073741823)
///   11 → 8 bytes (max 4611686018427387903)
enum H3VarInt {

    // MARK: - Encode

    /// Returns the minimum-width QUIC varint encoding of `value`.
    static func encode(_ value: UInt64) -> Data {
        switch value {
        case 0...0x3F:
            return Data([UInt8(value)])
        case 0...0x3FFF:
            let v = UInt16(value) | 0x4000
            return Data([UInt8(v >> 8), UInt8(v & 0xFF)])
        case 0...0x3FFF_FFFF:
            let v = UInt32(value) | 0x8000_0000
            return Data([
                UInt8((v >> 24) & 0xFF),
                UInt8((v >> 16) & 0xFF),
                UInt8((v >>  8) & 0xFF),
                UInt8( v        & 0xFF),
            ])
        default:
            let v = value | 0xC000_0000_0000_0000
            return Data([
                UInt8((v >> 56) & 0xFF),
                UInt8((v >> 48) & 0xFF),
                UInt8((v >> 40) & 0xFF),
                UInt8((v >> 32) & 0xFF),
                UInt8((v >> 24) & 0xFF),
                UInt8((v >> 16) & 0xFF),
                UInt8((v >>  8) & 0xFF),
                UInt8( v        & 0xFF),
            ])
        }
    }

    // MARK: - Decode

    /// Decodes the first varint from `data` starting at `offset`.
    /// Returns `(value, bytesConsumed)` or `nil` if the buffer is too short.
    static func decode(_ data: Data, at offset: Int = 0) -> (value: UInt64, length: Int)? {
        guard offset < data.count else { return nil }
        let firstByte = data[data.startIndex + offset]
        let prefix = firstByte >> 6

        switch prefix {
        case 0:
            return (UInt64(firstByte & 0x3F), 1)
        case 1:
            guard offset + 2 <= data.count else { return nil }
            let b0 = UInt64(firstByte & 0x3F)
            let b1 = UInt64(data[data.startIndex + offset + 1])
            return ((b0 << 8) | b1, 2)
        case 2:
            guard offset + 4 <= data.count else { return nil }
            var v: UInt64 = UInt64(firstByte & 0x3F)
            for i in 1..<4 { v = (v << 8) | UInt64(data[data.startIndex + offset + i]) }
            return (v, 4)
        case 3:
            guard offset + 8 <= data.count else { return nil }
            var v: UInt64 = UInt64(firstByte & 0x3F)
            for i in 1..<8 { v = (v << 8) | UInt64(data[data.startIndex + offset + i]) }
            return (v, 8)
        default:
            return nil
        }
    }

    /// How many bytes the varint encoding of `value` requires.
    static func encodedLength(_ value: UInt64) -> Int {
        switch value {
        case 0...0x3F:          return 1
        case 0...0x3FFF:        return 2
        case 0...0x3FFF_FFFF:   return 4
        default:                return 8
        }
    }
}
