import Foundation

// MARK: - Frame type constants (RFC 9114 §7.2)

enum H3FrameType: UInt64 {
    case data     = 0x00
    case headers  = 0x01
    case settings = 0x04
    // Reserved / unidirectional stream type tags:
    static let streamTypeControl: UInt64 = 0x00
}

// MARK: - Frame encoder

/// Encodes HTTP/3 frames as raw bytes.
enum H3FrameEncoder {

    /// Encodes a DATA frame: [type=0x00][varint length][payload].
    static func data(_ payload: Data) -> Data {
        var out = H3VarInt.encode(H3FrameType.data.rawValue)
        out += H3VarInt.encode(UInt64(payload.count))
        out += payload
        return out
    }

    /// Encodes a HEADERS frame: [type=0x01][varint length][encoded-field-section].
    static func headers(_ encodedFieldSection: Data) -> Data {
        var out = H3VarInt.encode(H3FrameType.headers.rawValue)
        out += H3VarInt.encode(UInt64(encodedFieldSection.count))
        out += encodedFieldSection
        return out
    }

    /// Encodes a SETTINGS frame with an empty settings list (use H/3 defaults).
    static func emptySettings() -> Data {
        var out = H3VarInt.encode(H3FrameType.settings.rawValue)
        out += H3VarInt.encode(0)   // length = 0
        return out
    }

    /// Encodes the unidirectional control stream header (stream type byte).
    /// Must be the very first byte written on the control stream.
    static func controlStreamHeader() -> Data {
        H3VarInt.encode(H3FrameType.streamTypeControl)
    }
}

// MARK: - Parsed frame

struct H3Frame {
    let type: UInt64
    let payload: Data
}

// MARK: - Streaming frame reader

/// Accumulates raw bytes from an NWConnection receive loop and yields complete H3 frames.
///
/// Usage:
/// ```swift
/// var reader = H3FrameReader()
/// reader.append(chunk)
/// while let frame = reader.next() { ... }
/// ```
struct H3FrameReader {
    private var buffer = Data()

    mutating func append(_ data: Data) {
        buffer.append(data)
    }

    /// Returns the next complete frame, or `nil` if more bytes are needed.
    mutating func next() -> H3Frame? {
        var offset = 0

        // Decode frame type varint.
        guard let (type, typeLen) = H3VarInt.decode(buffer, at: offset) else { return nil }
        offset += typeLen

        // Decode payload length varint.
        guard let (length, lenLen) = H3VarInt.decode(buffer, at: offset) else { return nil }
        offset += lenLen

        let total = offset + Int(length)
        guard buffer.count >= total else { return nil }

        let payload = buffer[buffer.startIndex + offset ..< buffer.startIndex + total]
        buffer.removeFirst(total)

        return H3Frame(type: type, payload: Data(payload))
    }

    var isEmpty: Bool { buffer.isEmpty }
}

// MARK: - gRPC 5-byte length-prefix framing

/// gRPC wire format for a single message (RFC gRPC over HTTP/2):
///   Byte 0:   compression flag (0 = uncompressed)
///   Bytes 1–4: big-endian uint32 message length
///   Bytes 5+:  serialised proto
enum GRPCFraming {

    static func encode(_ messageBytes: Data) -> Data {
        let len = UInt32(messageBytes.count)
        var out = Data(count: 5)
        out[0] = 0x00   // no compression
        out[1] = UInt8((len >> 24) & 0xFF)
        out[2] = UInt8((len >> 16) & 0xFF)
        out[3] = UInt8((len >>  8) & 0xFF)
        out[4] = UInt8( len        & 0xFF)
        out.append(messageBytes)
        return out
    }

    /// Attempts to decode the first gRPC message from `data`.
    /// Returns `(messageData, totalBytesConsumed)` or `nil` if incomplete.
    static func decode(_ data: Data) -> (message: Data, consumed: Int)? {
        guard data.count >= 5 else { return nil }
        // byte 0: compression flag (we don't support compression, ignore for now)
        let len = Int(data[1]) << 24 | Int(data[2]) << 16 | Int(data[3]) << 8 | Int(data[4])
        guard data.count >= 5 + len else { return nil }
        let message = Data(data[5 ..< 5 + len])
        return (message, 5 + len)
    }
}
