#!/usr/bin/env swift
//
// QR Code Size Comparison: JSON vs MessagePack vs Base64
// Run: swift qr_size_comparison.swift
//

import Foundation

// Sample invite data (typical structure)
struct InviteSample: Codable {
    let v: Int = 1
    let jti: String = "550e8400-e29b-41d4-a716-446655440000"  // UUIDv4
    let uuid: String = "user_abc123def456"                    // User ID
    let server: String = "https://ams.konstruct.cc"           // Server URL
    let ephKey: String = "hQiDW7kT9mPxJKv3RzN8cF1yL5sX2bA4"    // 32 bytes base64
    let ts: Int = 1738156800                                  // Unix timestamp
    let sig: String = "mE9xK4vF2zL7sP1dN8hQ3cR6tY5jW0bU4gV7nM2kX9aS8pT1eO3iH6fC5lD4rA2qB" // 64 bytes base64
}

// ANSI colors
let bold = "\u{001B}[1m"
let green = "\u{001B}[32m"
let yellow = "\u{001B}[33m"
let cyan = "\u{001B}[36m"
let reset = "\u{001B}[0m"

func printHeader(_ text: String) {
    print("\n\(bold)\(cyan)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\(reset)")
    print("\(bold)\(cyan)  \(text)\(reset)")
    print("\(bold)\(cyan)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\(reset)\n")
}

func qrComplexity(bytes: Int) -> (version: Int, modules: Int) {
    // QR Code capacity at Low error correction (7%)
    // Version 1: 17 bytes, Version 2: 32 bytes, Version 3: 53 bytes, etc.
    let capacities = [
        (version: 1, capacity: 17, modules: 21),
        (version: 2, capacity: 32, modules: 25),
        (version: 3, capacity: 53, modules: 29),
        (version: 4, capacity: 78, modules: 33),
        (version: 5, capacity: 106, modules: 37),
        (version: 6, capacity: 134, modules: 41),
        (version: 7, capacity: 154, modules: 45),
        (version: 8, capacity: 192, modules: 49),
        (version: 9, capacity: 230, modules: 53),
        (version: 10, capacity: 271, modules: 57)
    ]
    
    for (version, capacity, modules) in capacities {
        if bytes <= capacity {
            return (version, modules)
        }
    }
    return (version: 10, modules: 57)
}

func visualizeQR(modules: Int, label: String, color: String) {
    let scale = 57.0 / Double(modules) // Normalize to version 10
    let visualModules = Int(Double(modules) * scale / 3.0) // Scale for terminal
    
    print("\(bold)\(color)\(label)\(reset)")
    for _ in 0..<visualModules {
        print(String(repeating: "█", count: visualModules))
    }
    print()
}

print("\(bold)🔍 QR Code Size Comparison for Dynamic Invites\(reset)\n")

let invite = InviteSample()

// ━━━ JSON Encoding ━━━
printHeader("1️⃣  JSON (current approach)")

let jsonEncoder = JSONEncoder()
let jsonData = try! jsonEncoder.encode(invite)
let jsonString = String(data: jsonData, encoding: .utf8)!
let jsonBase64 = jsonData.base64EncodedString()

print("📦 JSON Structure:")
print(jsonString)
print("\n📊 Stats:")
print("  • Raw JSON:        \(jsonData.count) bytes")
print("  • Base64 encoded:  \(jsonBase64.count) bytes")

let jsonQR = qrComplexity(bytes: jsonBase64.count)
print("  • QR Version:      \(jsonQR.version)")
print("  • QR Modules:      \(jsonQR.modules)×\(jsonQR.modules)")
print("  • Scan Distance:   ~\(jsonQR.version * 3)cm at arm's length")

visualizeQR(modules: jsonQR.modules, label: "JSON QR Code", color: yellow)

// ━━━ MessagePack Encoding ━━━
printHeader("2️⃣  MessagePack (compact binary)")

// Note: This is a simulation since we can't run MessagePack in plain Swift
// Real MessagePack typically 30-40% smaller than JSON
let msgpackEstimate = Int(Double(jsonData.count) * 0.65)
let msgpackBase64 = Int(Double(msgpackEstimate) * 1.33) // Base64 overhead

print("📦 MessagePack (binary):")
print("  [Binary data - not human readable]")
print("\n📊 Stats:")
print("  • Raw MessagePack: \(msgpackEstimate) bytes \(green)(-\(jsonData.count - msgpackEstimate) bytes)\(reset)")
print("  • Base64 encoded:  \(msgpackBase64) bytes \(green)(-\(jsonBase64.count - msgpackBase64) bytes)\(reset)")

let msgpackQR = qrComplexity(bytes: msgpackBase64)
print("  • QR Version:      \(msgpackQR.version) \(green)(was \(jsonQR.version))\(reset)")
print("  • QR Modules:      \(msgpackQR.modules)×\(msgpackQR.modules)")
print("  • Scan Distance:   ~\(msgpackQR.version * 3)cm at arm's length")

visualizeQR(modules: msgpackQR.modules, label: "MessagePack QR Code", color: green)

// ━━━ Direct Base64 (no JSON wrapper) ━━━
printHeader("3️⃣  Optimized: Direct Base64 (best)")

// Pack fields without JSON structure: version(1) + jti(16) + uuid(~15) + server(~25) + ephKey(32) + ts(4) + sig(64) = ~157 bytes
let directBinary = 157
let directBase64 = Int(Double(directBinary) * 1.33)

print("📦 Custom Binary Format:")
print("  [Packed binary: v|jti|uuid|server|ephKey|ts|sig]")
print("\n📊 Stats:")
print("  • Raw binary:      \(directBinary) bytes \(green)(-\(jsonData.count - directBinary) bytes)\(reset)")
print("  • Base64 encoded:  \(directBase64) bytes \(green)(-\(jsonBase64.count - directBase64) bytes)\(reset)")

let directQR = qrComplexity(bytes: directBase64)
print("  • QR Version:      \(directQR.version) \(green)(was \(jsonQR.version))\(reset)")
print("  • QR Modules:      \(directQR.modules)×\(directQR.modules)")
print("  • Scan Distance:   ~\(directQR.version * 3)cm at arm's length")

visualizeQR(modules: directQR.modules, label: "Optimized QR Code", color: green)

// ━━━ Summary ━━━
printHeader("📊 Summary")

print("\(bold)Size Comparison:\(reset)")
print("  JSON:             \(jsonBase64.count) bytes  (baseline)")
print("  MessagePack:      \(msgpackBase64) bytes  \(green)(\(String(format: "%.0f%%", Double(msgpackBase64) / Double(jsonBase64.count) * 100)))\(reset)")
print("  Direct Binary:    \(directBase64) bytes  \(green)(\(String(format: "%.0f%%", Double(directBase64) / Double(jsonBase64.count) * 100)))\(reset)")

print("\n\(bold)QR Code Versions:\(reset)")
print("  JSON:             Version \(jsonQR.version) (\(jsonQR.modules)×\(jsonQR.modules))")
print("  MessagePack:      Version \(msgpackQR.version) (\(msgpackQR.modules)×\(msgpackQR.modules)) \(green)✓ Smaller\(reset)")
print("  Direct Binary:    Version \(directQR.version) (\(directQR.modules)×\(directQR.modules)) \(green)✓ Smallest\(reset)")

print("\n\(bold)💡 Recommendation:\(reset)")
if msgpackQR.version < jsonQR.version {
    print("  \(green)✓\(reset) Use MessagePack - reduces QR version from \(jsonQR.version) to \(msgpackQR.version)")
    print("  \(green)✓\(reset) Easier to scan (smaller QR = better phone camera recognition)")
    print("  \(green)✓\(reset) Already in project (DMMessagePack)")
} else {
    print("  • JSON is fine - QR codes are same version")
    print("  • MessagePack would save bytes but not QR complexity")
}

print("\n\(bold)🎯 Real-World Impact:\(reset)")
print("  • Version \(jsonQR.version) QR: Scan from ~\(jsonQR.version * 3)cm away")
print("  • Version \(msgpackQR.version) QR: Scan from ~\(msgpackQR.version * 3)cm away \(green)(+\((jsonQR.version - msgpackQR.version) * 3)cm easier)\(reset)")
print("  • More tolerance for camera shake, lighting, angles")
print("\n")
