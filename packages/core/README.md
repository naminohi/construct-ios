# Construct Core

Core Rust library for Construct Messenger with end-to-end encryption.

## 🚀 Quick Start

### Building the library
```bash
cargo build --lib
cargo test --lib
```

### Generating Swift bindings for iOS/macOS
```bash
uniffi-bindgen generate --language swift \
  src/construct_core.udl \
  --out-dir ../ios/ConstructCore/Generated
```

## 🔧 UniFFI Setup

This project uses **UniFFI 0.28.3** for generating language bindings.

**Important:** Due to Rust 1.82+ changes, we use automatic patching in `build.rs`. This is transparent and works automatically.

### Quick health check
```bash
./check_uniffi_health.sh
```

### Documentation
- **Quick Reference:** [UNIFFI_QUICK_REFERENCE.md](UNIFFI_QUICK_REFERENCE.md) - Daily commands and troubleshooting
- **Full Guide:** [UNIFFI_VERSION_GUIDE.md](../../UNIFFI_VERSION_GUIDE.md) - Complete analysis and migration plan

## 📦 Architecture

```
src/
├── crypto/              # Cryptographic primitives
│   ├── handshake/       # X3DH key agreement
│   ├── messaging/       # Double Ratchet protocol
│   └── suites/          # Crypto suites (Classic, PQ)
├── traffic_protection/  # Traffic analysis protection (NEW!)
│   ├── padding.rs       # Message padding (PKCS7-style)
│   ├── cover_traffic.rs # Dummy messages
│   └── timing.rs        # Timing jitter
├── protocol/            # Wire protocol
└── uniffi_bindings.rs   # UniFFI interface
```

## 🔐 Features

### Implemented
- ✅ **X3DH** key agreement protocol
- ✅ **Double Ratchet** secure messaging
- ✅ **Message Padding** (traffic analysis protection)
- ✅ **Crypto-agility** (multiple cipher suites)
- ✅ **UniFFI bindings** for iOS/macOS

### In Progress
- 🔄 **Cover Traffic** (energy-efficient dummy messages)
- 🔄 **Timing Protection** (jittered intervals)

### Planned
- 📋 **Post-Quantum** hybrid mode (ML-KEM + X25519)

## 🧪 Testing

```bash
# All tests
cargo test --lib

# Specific module
cargo test --lib crypto::messaging

# With output
cargo test --lib -- --nocapture
```

## 📚 Documentation

- Architecture: `ARCHITECTURE_TODOS.md` (in root)
- UniFFI Setup: `UNIFFI_VERSION_GUIDE.md` (in root)
- Traffic Protection Plan: `TRAFFIC_PROTECTION_IMPLEMENTATION_PLAN.md` (in root)

## 🤝 Contributing

1. Read the architecture docs
2. Run `./check_uniffi_health.sh` to ensure setup is correct
3. Make changes
4. Run tests: `cargo test --lib`
5. Generate Swift bindings if .udl changed

## ⚡ Energy Efficiency

Traffic protection features are designed with mobile battery life in mind:
- **Padding**: Zero overhead (only during encrypt/decrypt)
- **Cover Traffic**: Battery-aware with adaptive intervals
- **Timing Jitter**: Minimal CPU wake-ups

See `src/traffic_protection/` for implementation details.

---

**Status:** ✅ Production Ready (Core Crypto)
**UniFFI Version:** 0.28.3
**Rust Version:** 1.92.0
