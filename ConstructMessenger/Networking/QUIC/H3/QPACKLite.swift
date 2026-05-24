import Foundation

// MARK: - QPACK static table (RFC 9204 Appendix A, entries 0–98)
// We use static-table-only encoding: no dynamic table, no encoder/decoder streams required.
// This is sufficient for all gRPC request and response headers.

/// Lightweight QPACK encoder/decoder using only the static table.
///
/// **Encoding**: emits Indexed Field Line (0xC0 | index) for headers that match a static
/// entry, and Literal Field Line With Name Reference or Literal Field Line With Literal Name
/// for everything else.
///
/// **Decoding**: parses Required Insert Count + S bit prefix, then reads field lines until
/// the payload is exhausted. Supports Huffman-encoded strings (RFC 7541 Appendix B).
enum QPACKLite {

    // MARK: - RFC 7541 Appendix B Huffman table
    // Entries are (code, bit_length) for symbols 0–255 + EOS at index 256.
    // Identical to HPACK (HTTP/2) — reused by QPACK (HTTP/3) per RFC 9204.
    private static let huffmanTable: [(UInt32, Int)] = [
        (0x1ff8, 13), (0x7fffd8, 23), (0xfffffe2, 28), (0xfffffe3, 28), (0xfffffe4, 28),
        (0xfffffe5, 28), (0xfffffe6, 28), (0xfffffe7, 28), (0xfffffe8, 28), (0xffffea, 24),
        (0x3ffffffc, 30), (0xfffffe9, 28), (0xfffffea, 28), (0x3ffffffd, 30), (0xfffffeb, 28),
        (0xfffffec, 28), (0xfffffed, 28), (0xfffffee, 28), (0xfffffef, 28), (0xffffff0, 28),
        (0xffffff1, 28), (0xffffff2, 28), (0x3ffffffe, 30), (0xffffff3, 28), (0xffffff4, 28),
        (0xffffff5, 28), (0xffffff6, 28), (0xffffff7, 28), (0xffffff8, 28), (0xffffff9, 28),
        (0xffffffa, 28), (0xffffffb, 28), (0x14, 6), (0x3f8, 10), (0x3f9, 10), (0xffa, 12),
        (0x1ff9, 13), (0x15, 6), (0xf8, 8), (0x7fa, 11), (0x3fa, 10), (0x3fb, 10),
        (0xf9, 8), (0x7fb, 11), (0xfa, 8), (0x16, 6), (0x17, 6), (0x18, 6),
        (0x0, 5), (0x1, 5), (0x2, 5), (0x19, 6), (0x1a, 6), (0x1b, 6),
        (0x1c, 6), (0x1d, 6), (0x1e, 6), (0x1f, 6), (0x5c, 7), (0xfb, 8),
        (0x7ffc, 15), (0x20, 6), (0xffb, 12), (0x3fc, 10), (0x1ffa, 13), (0x21, 6),
        (0x5d, 7), (0x5e, 7), (0x5f, 7), (0x60, 7), (0x61, 7), (0x62, 7),
        (0x63, 7), (0x64, 7), (0x65, 7), (0x66, 7), (0x67, 7), (0x68, 7),
        (0x69, 7), (0x6a, 7), (0x6b, 7), (0x6c, 7), (0x6d, 7), (0x6e, 7),
        (0x6f, 7), (0x70, 7), (0x71, 7), (0x72, 7), (0xfc, 8), (0x73, 7),
        (0xfd, 8), (0x1ffb, 13), (0x7fff0, 19), (0x1ffc, 13), (0x3ffc, 14), (0x22, 6),
        (0x7ffd, 15), (0x3, 5), (0x23, 6), (0x4, 5), (0x24, 6), (0x5, 5),
        (0x25, 6), (0x26, 6), (0x27, 6), (0x6, 5), (0x74, 7), (0x75, 7),
        (0x28, 6), (0x29, 6), (0x2a, 6), (0x7, 5), (0x2b, 6), (0x76, 7),
        (0x2c, 6), (0x8, 5), (0x9, 5), (0x2d, 6), (0x77, 7), (0x78, 7),
        (0x79, 7), (0x7a, 7), (0x7b, 7), (0x7ffe, 15), (0x7fc, 11), (0x3ffd, 14),
        (0x1ffd, 13), (0xffffffc, 28), (0xfffe6, 20), (0x3fffd2, 22), (0xfffe7, 20), (0xfffe8, 20),
        (0x3fffd3, 22), (0x3fffd4, 22), (0x3fffd5, 22), (0x7fffd9, 23), (0x3fffd6, 22), (0x7fffda, 23),
        (0x7fffdb, 23), (0x7fffdc, 23), (0x7fffdd, 23), (0x7fffde, 23), (0xffffeb, 24), (0x7fffdf, 23),
        (0xffffec, 24), (0xffffed, 24), (0x3fffd7, 22), (0x7fffe0, 23), (0xffffee, 24), (0x7fffe1, 23),
        (0x7fffe2, 23), (0x7fffe3, 23), (0x7fffe4, 23), (0x1fffdc, 21), (0x3fffd8, 22), (0x7fffe5, 23),
        (0x3fffd9, 22), (0x7fffe6, 23), (0x7fffe7, 23), (0xffffef, 24), (0x3fffda, 22), (0x1fffdd, 21),
        (0xfffe9, 20), (0x3fffdb, 22), (0x3fffdc, 22), (0x7fffe8, 23), (0x7fffe9, 23), (0x1fffde, 21),
        (0x7fffea, 23), (0x3fffdd, 22), (0x3fffde, 22), (0xfffff0, 24), (0x1fffdf, 21), (0x3fffdf, 22),
        (0x7fffeb, 23), (0x7fffec, 23), (0x1fffe0, 21), (0x1fffe1, 21), (0x3fffe0, 22), (0x1fffe2, 21),
        (0x7fffed, 23), (0x3fffe1, 22), (0x7fffee, 23), (0x7fffef, 23), (0xfffea, 20), (0x3fffe2, 22),
        (0x3fffe3, 22), (0x3fffe4, 22), (0x7ffff0, 23), (0x3fffe5, 22), (0x3fffe6, 22), (0x7ffff1, 23),
        (0x3ffffe0, 26), (0x3ffffe1, 26), (0xfffeb, 20), (0x7fff1, 19), (0x3fffe7, 22), (0x7ffff2, 23),
        (0x3fffe8, 22), (0x1ffffec, 25), (0x3ffffe2, 26), (0x3ffffe3, 26), (0x3ffffe4, 26), (0x7ffffde, 27),
        (0x7ffffdf, 27), (0x3ffffe5, 26), (0xfffff1, 24), (0x1ffffed, 25), (0x7fff2, 19), (0x1fffe3, 21),
        (0x3ffffe6, 26), (0x7ffffe0, 27), (0x7ffffe1, 27), (0x3ffffe7, 26), (0x7ffffe2, 27), (0xfffff2, 24),
        (0x1fffe4, 21), (0x1fffe5, 21), (0x3ffffe8, 26), (0x3ffffe9, 26), (0xffffffd, 28), (0x7ffffe3, 27),
        (0x7ffffe4, 27), (0x7ffffe5, 27), (0xfffec, 20), (0xfffff3, 24), (0xfffed, 20), (0x1fffe6, 21),
        (0x3fffe9, 22), (0x1fffe7, 21), (0x1fffe8, 21), (0x7ffff3, 23), (0x3fffea, 22), (0x3fffeb, 22),
        (0x1ffffee, 25), (0x1ffffef, 25), (0xfffff4, 24), (0xfffff5, 24), (0x3ffffea, 26), (0x7ffff4, 23),
        (0x3ffffeb, 26), (0x7ffffe6, 27), (0x3ffffec, 26), (0x3ffffed, 26), (0x7ffffe7, 27), (0x7ffffe8, 27),
        (0x7ffffe9, 27), (0x7ffffea, 27), (0x7ffffeb, 27), (0xffffffe, 28), (0x7ffffec, 27), (0x7ffffed, 27),
        (0x7ffffee, 27), (0x7ffffef, 27), (0x7fffff0, 27), (0x3ffffee, 26),
        (0x3fffffff, 30), // EOS (symbol 256)
    ]

    /// Decodes a Huffman-encoded byte sequence using the RFC 7541 code table.
    /// Returns nil if the encoded data is malformed.
    static func huffmanDecode(_ encoded: Data) -> String? {
        guard !encoded.isEmpty else { return "" }

        var accumulated: UInt64 = 0
        var bitCount = 0
        var output: [UInt8] = []
        output.reserveCapacity(encoded.count * 2)

        for byte in encoded {
            accumulated = (accumulated << 8) | UInt64(byte)
            bitCount += 8

            // Drain all symbols that can be decoded from the current bit accumulator.
            var decoded = true
            while decoded && bitCount > 0 {
                decoded = false
                for sym in 0..<257 {
                    let (code, nbits) = huffmanTable[sym]
                    guard nbits <= bitCount else { continue }
                    let topBits = accumulated >> (bitCount - nbits)
                    if topBits == UInt64(code) {
                        if sym == 256 { return nil } // EOS mid-stream = malformed
                        output.append(UInt8(sym))
                        bitCount -= nbits
                        accumulated = bitCount > 0 ? accumulated & ((UInt64(1) << bitCount) - 1) : 0
                        decoded = true
                        break
                    }
                }
            }
        }

        // Remaining bits (≤ 7) must be all-ones EOS padding.
        if bitCount > 7 { return nil }

        return String(bytes: output, encoding: .utf8)
    }

    // MARK: - Static table (value = nil means match any value for that name)

    private static let staticTable: [(name: String, value: String?)] = [
        /* 0 */  (":authority", nil),
        /* 1 */  (":path", "/"),
        /* 2 */  ("age", "0"),
        /* 3 */  ("content-disposition", nil),
        /* 4 */  ("content-length", "0"),
        /* 5 */  ("cookie", nil),
        /* 6 */  ("date", nil),
        /* 7 */  ("etag", nil),
        /* 8 */  ("if-modified-since", nil),
        /* 9 */  ("if-none-match", nil),
        /* 10 */ ("last-modified", nil),
        /* 11 */ ("link", nil),
        /* 12 */ ("location", nil),
        /* 13 */ ("referer", nil),
        /* 14 */ ("set-cookie", nil),
        /* 15 */ (":method", "CONNECT"),
        /* 16 */ (":method", "DELETE"),
        /* 17 */ (":method", "GET"),
        /* 18 */ (":method", "HEAD"),
        /* 19 */ (":method", "OPTIONS"),
        /* 20 */ (":method", "POST"),
        /* 21 */ (":method", "PUT"),
        /* 22 */ (":scheme", "http"),
        /* 23 */ (":scheme", "https"),
        /* 24 */ (":status", "103"),
        /* 25 */ (":status", "200"),
        /* 26 */ (":status", "304"),
        /* 27 */ (":status", "404"),
        /* 28 */ (":status", "503"),
        /* 29 */ ("accept", "*/*"),
        /* 30 */ ("accept", "application/dns-message"),
        /* 31 */ ("accept-encoding", "gzip, deflate, br"),
        /* 32 */ ("accept-ranges", "bytes"),
        /* 33 */ ("access-control-allow-headers", "cache-control"),
        /* 34 */ ("access-control-allow-headers", "content-type"),
        /* 35 */ ("access-control-allow-origin", "*"),
        /* 36 */ ("cache-control", "max-age=0"),
        /* 37 */ ("cache-control", "max-age=2592000"),
        /* 38 */ ("cache-control", "max-age=604800"),
        /* 39 */ ("cache-control", "no-cache"),
        /* 40 */ ("cache-control", "no-store"),
        /* 41 */ ("cache-control", "public, max-age=31536000"),
        /* 42 */ ("content-encoding", "br"),
        /* 43 */ ("content-encoding", "gzip"),
        /* 44 */ ("content-type", "application/dns-message"),
        /* 45 */ ("content-type", "application/javascript"),
        /* 46 */ ("content-type", "application/json"),
        /* 47 */ ("content-type", "application/x-www-form-urlencoded"),
        /* 48 */ ("content-type", "image/gif"),
        /* 49 */ ("content-type", "image/jpeg"),
        /* 50 */ ("content-type", "image/png"),
        /* 51 */ ("content-type", "text/css"),
        /* 52 */ ("content-type", "text/html; charset=utf-8"),
        /* 53 */ ("content-type", "text/plain"),
        /* 54 */ ("content-type", "text/plain;charset=utf-8"),
        /* 55 */ ("range", "bytes=0-"),
        /* 56 */ ("strict-transport-security", "max-age=31536000"),
        /* 57 */ ("strict-transport-security", "max-age=31536000; includesubdomains"),
        /* 58 */ ("strict-transport-security", "max-age=31536000; includesubdomains; preload"),
        /* 59 */ ("vary", "accept-encoding"),
        /* 60 */ ("vary", "origin"),
        /* 61 */ ("x-content-type-options", "nosniff"),
        /* 62 */ ("x-xss-protection", "1; mode=block"),
        /* 63 */ (":status", "100"),
        /* 64 */ (":status", "204"),
        /* 65 */ (":status", "206"),
        /* 66 */ (":status", "302"),
        /* 67 */ (":status", "400"),
        /* 68 */ (":status", "403"),
        /* 69 */ (":status", "421"),
        /* 70 */ (":status", "425"),
        /* 71 */ (":status", "500"),
        /* 72 */ ("accept-language", nil),
        /* 73 */ ("access-control-allow-credentials", "FALSE"),
        /* 74 */ ("access-control-allow-credentials", "TRUE"),
        /* 75 */ ("access-control-allow-headers", "*"),
        /* 76 */ ("access-control-allow-methods", "get"),
        /* 77 */ ("access-control-allow-methods", "get, post, options"),
        /* 78 */ ("access-control-allow-methods", "options"),
        /* 79 */ ("access-control-expose-headers", "content-length"),
        /* 80 */ ("access-control-request-headers", "content-type"),
        /* 81 */ ("access-control-request-method", "get"),
        /* 82 */ ("access-control-request-method", "post"),
        /* 83 */ ("alt-svc", "clear"),
        /* 84 */ ("authorization", nil),
        /* 85 */ ("content-security-policy", "script-src 'none'; object-src 'none'; base-uri 'none'"),
        /* 86 */ ("early-data", "1"),
        /* 87 */ ("expect-ct", nil),
        /* 88 */ ("forwarded", nil),
        /* 89 */ ("if-range", nil),
        /* 90 */ ("origin", nil),
        /* 91 */ ("purpose", "prefetch"),
        /* 92 */ ("server", nil),
        /* 93 */ ("timing-allow-origin", "*"),
        /* 94 */ ("upgrade-insecure-requests", "1"),
        /* 95 */ ("user-agent", nil),
        /* 96 */ ("x-forwarded-for", nil),
        /* 97 */ ("x-frame-options", "deny"),
        /* 98 */ ("x-frame-options", "sameorigin"),
    ]

    // MARK: - Encode

    /// Encodes a list of header name-value pairs as a QPACK-encoded field section.
    /// Prepends the required QPACK prefix (Required Insert Count = 0, S = 0).
    static func encodeHeaders(_ headers: [(name: String, value: String)]) -> Data {
        var out = Data()
        // QPACK Required Insert Count = 0 (static-only), Delta Base = 0.
        out.append(0x00)    // Required Insert Count (0 = static only)
        out.append(0x00)    // Delta Base (sign=0, delta=0)

        for (name, value) in headers {
            if let idx = staticIndex(name: name, value: value) {
                // Indexed Field Line: 1-bit prefix 1, static bit = 1 → 0xC0 | index
                if idx < 64 {
                    out.append(0xC0 | UInt8(idx))
                } else {
                    // Two-byte indexed: 0xC0 prefix with 6-bit value in first byte,
                    // then continuation. For static table (max idx=98) we encode as:
                    // first byte: 0xFF (all 6 low bits set = 63, means "add next")
                    // second byte: (idx - 63) with high bit clear
                    out.append(0xFF)
                    out.append(UInt8(idx - 63))
                }
            } else if let nameIdx = staticNameIndex(name: name) {
                // Literal Field Line With Name Reference (static): 0101_nnnn nvalue...
                // Pattern: 0101 | (static=1 → high bit of index byte set) ...
                // Simplified: use "Literal With Name Reference" format (prefix 0x50 | nameIdx)
                encodeLiteralWithNameRef(nameIdx: nameIdx, value: value, into: &out)
            } else {
                // Literal Field Line With Literal Name (prefix 0x20, never-indexed = 0x10)
                encodeLiteralWithLiteralName(name: name, value: value, into: &out)
            }
        }
        return out
    }

    // MARK: - Decode

    struct HeaderField: Equatable {
        let name: String
        let value: String
    }

    /// Decodes a QPACK-encoded field section. Returns decoded headers or nil on parse error.
    static func decodeHeaders(_ data: Data) -> [HeaderField]? {
        guard data.count >= 2 else { return nil }
        var offset = 0

        // Skip Required Insert Count and Delta Base (both varint-encoded in QPACK prefix).
        guard let (_, ricLen) = parseIntegerHPACK(data, offset: offset, prefixBits: 8) else { return nil }
        offset += ricLen
        guard let (_, dbLen) = parseIntegerHPACK(data, offset: offset, prefixBits: 7) else { return nil }
        offset += dbLen

        var headers: [HeaderField] = []

        while offset < data.count {
            let byte = data[data.startIndex + offset]

            if byte & 0x80 != 0 {
                // Indexed Field Line (static): first bit = 1
                let isStatic = (byte & 0x40) != 0
                guard let (idx, len) = parseIntegerHPACK(data, offset: offset, prefixBits: 6) else { return nil }
                offset += len
                if isStatic, Int(idx) < staticTable.count {
                    let entry = staticTable[Int(idx)]
                    headers.append(HeaderField(name: entry.name, value: entry.value ?? ""))
                }
                // Dynamic table entries: skip (we don't maintain one)

            } else if byte & 0x40 != 0 {
                // Literal Field Line With Name Reference
                let isStatic = (byte & 0x10) != 0
                guard let (nameIdx, nameLen) = parseIntegerHPACK(data, offset: offset, prefixBits: 4) else { return nil }
                offset += nameLen
                guard let (value, valueLen) = parseString(data, offset: offset) else { return nil }
                offset += valueLen
                if isStatic, Int(nameIdx) < staticTable.count {
                    let name = staticTable[Int(nameIdx)].name
                    headers.append(HeaderField(name: name, value: value))
                }

            } else {
                // Literal Field Line With Literal Name (RFC 9204 §3.2.6)
                // Prefix byte layout: [0][0][1][N][H_name][NameLen 2:0]
                // - H_name (bit 3): 1 = name is Huffman-encoded
                // - NameLen uses a 3-bit prefix integer starting at bits [2:0] of this byte
                let hName = (byte & 0x08) != 0
                guard let (nameByteCount, nameIntLen) = parseIntegerHPACK(data, offset: offset, prefixBits: 3) else { return nil }
                offset += nameIntLen
                let nameEnd = offset + Int(nameByteCount)
                guard nameEnd <= data.count else { return nil }
                let nameBytes = Data(data[data.startIndex + offset ..< data.startIndex + nameEnd])
                offset = nameEnd
                guard let name = hName ? huffmanDecode(nameBytes) : String(bytes: nameBytes, encoding: .utf8) else { return nil }
                guard let (value, valueLen) = parseString(data, offset: offset) else { return nil }
                offset += valueLen
                headers.append(HeaderField(name: name, value: value))
            }
        }

        return headers
    }

    // MARK: - Private helpers

    private static func staticIndex(name: String, value: String) -> Int? {
        staticTable.firstIndex(where: { $0.name == name && $0.value == value })
    }

    private static func staticNameIndex(name: String) -> Int? {
        staticTable.firstIndex(where: { $0.name == name })
    }

    private static func encodeLiteralWithNameRef(nameIdx: Int, value: String, into out: inout Data) {
        // RFC 9204 §3.2.3 — Literal Field Line With Name Reference (static table, N=0).
        // Prefix: [0][1][N=0][T=1][Index 3:0] → high nibble 0x50, 4-bit HPACK integer for nameIdx.
        // Max value in 4-bit prefix = 15 (0x0F). If nameIdx < 15, encode inline. Otherwise overflow.
        if nameIdx < 15 {
            out.append(0x50 | UInt8(nameIdx))
        } else {
            out.append(0x5F)                                // all 4 prefix bits = 1 (overflow indicator)
            var overflow = nameIdx - 15
            while overflow >= 128 {
                out.append(UInt8((overflow & 0x7F) | 0x80))
                overflow >>= 7
            }
            out.append(UInt8(overflow))
        }
        out.append(contentsOf: encodeStringLiteral(Data(value.utf8)))
    }

    private static func encodeLiteralWithLiteralName(name: String, value: String, into out: inout Data) {
        // RFC 9204 §3.2.6 — Literal Field Line With Literal Name (N=0, H_name=0).
        // Prefix byte layout: [0][0][1][N=0][H_name=0][NameLen 2:0]
        //   → base = 0x20; NameLen is a 3-bit HPACK integer (max inline = 7).
        // The name bytes follow the prefix directly (no separate string-literal framing for name).
        // The value uses standard 7-bit string literal format.
        let nameBytes = Data(name.utf8)
        let nameLen = nameBytes.count
        if nameLen < 7 {
            out.append(0x20 | UInt8(nameLen))
        } else {
            out.append(0x27)                                // all 3 NameLen prefix bits = 1 (overflow)
            var overflow = nameLen - 7
            while overflow >= 128 {
                out.append(UInt8((overflow & 0x7F) | 0x80))
                overflow >>= 7
            }
            out.append(UInt8(overflow))
        }
        out.append(contentsOf: nameBytes)
        out.append(contentsOf: encodeStringLiteral(Data(value.utf8)))
    }

    // HPACK/QPACK integer encoding (RFC 7541 §5.1, reused by QPACK for string lengths).
    private static func encodeIntegerHPACK(_ value: UInt64, prefixBits: Int) -> Data {
        let maxPrefix = UInt64((1 << prefixBits) - 1)
        if value < maxPrefix {
            return Data([UInt8(value)])
        }
        var out = Data([UInt8(maxPrefix)])
        var remaining = value - maxPrefix
        while remaining >= 128 {
            out.append(UInt8((remaining & 0x7F) | 0x80))
            remaining >>= 7
        }
        out.append(UInt8(remaining))
        return out
    }

    private static func parseIntegerHPACK(_ data: Data, offset: Int, prefixBits: Int) -> (value: UInt64, bytesRead: Int)? {
        guard offset < data.count else { return nil }
        let mask = UInt64((1 << prefixBits) - 1)
        var value = UInt64(data[data.startIndex + offset]) & mask
        var pos = offset + 1
        guard value == mask else { return (value, pos - offset) }

        var shift: UInt64 = 0
        repeat {
            guard pos < data.count else { return nil }
            let b = UInt64(data[data.startIndex + pos])
            value += (b & 0x7F) << shift
            shift += 7
            pos += 1
            if b & 0x80 == 0 { break }
        } while pos < data.count
        return (value, pos - offset)
    }

    private static func encodeStringLiteral(_ bytes: Data) -> Data {
        // H-bit = 0 (no Huffman), then HPACK integer for length, then raw bytes.
        var out = Data()
        out.append(contentsOf: encodeIntegerHPACK(UInt64(bytes.count), prefixBits: 7))
        out.append(contentsOf: bytes)
        return out
    }

    /// Parses an HPACK/QPACK string literal: [H][Length (7+)][bytes].
    /// H-bit (bit 7 of first byte) indicates Huffman encoding.
    private static func parseString(_ data: Data, offset: Int) -> (value: String, bytesRead: Int)? {
        guard offset < data.count else { return nil }
        let huffman = (data[data.startIndex + offset] & 0x80) != 0
        guard let (length, lenBytes) = parseIntegerHPACK(data, offset: offset, prefixBits: 7) else { return nil }
        let start = offset + lenBytes
        let end = start + Int(length)
        guard end <= data.count else { return nil }
        let raw = Data(data[data.startIndex + start ..< data.startIndex + end])
        if huffman {
            guard let str = huffmanDecode(raw) else { return nil }
            return (str, lenBytes + Int(length))
        }
        guard let str = String(bytes: raw, encoding: .utf8) else { return nil }
        return (str, lenBytes + Int(length))
    }
}
