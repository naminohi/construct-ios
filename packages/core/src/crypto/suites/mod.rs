//! Криптографические наборы (Crypto Suites)
//!
//! Этот модуль содержит различные реализации CryptoProvider trait.
//!
//! ## Доступные наборы
//!
//! ### Classic Suite (текущий)
//! - **KEM**: X25519 (ECDH на Curve25519)
//! - **Signatures**: Ed25519
//! - **AEAD**: ChaCha20-Poly1305
//! - **KDF**: HKDF-SHA256
//! - **Suite ID**: 1
//!
//! ### Hybrid Suite (будущее - Q2 2026)
//! - **KEM**: X25519 + ML-KEM-768 (Kyber)
//! - **Signatures**: Ed25519 + ML-DSA-65 (Dilithium)
//! - **AEAD**: ChaCha20-Poly1305
//! - **KDF**: HKDF-SHA256
//! - **Suite ID**: 2
//!
//! ## Выбор suite
//!
//! ```rust
//! use construct_core::crypto::suites::classic::ClassicSuiteProvider;
//! use construct_core::crypto::provider::CryptoProvider;
//!
//! // Classic suite для текущего использования
//! type MySuite = ClassicSuiteProvider;
//!
//! // Генерация ключей
//! let (private_key, public_key) = MySuite::generate_kem_keys()?;
//! ```

pub mod classic;

// Будущее: pub mod hybrid;
