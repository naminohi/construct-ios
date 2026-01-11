// Construct Messenger Core
// Rust/WASM engine with end-to-end encryption

#![warn(clippy::all)]
#![allow(clippy::too_many_arguments)]
#![allow(unsafe_attr_outside_unsafe)]  // Allow UniFFI 0.28 generated code on Rust 1.82+

// UniFFI bindings for iOS/macOS
#[cfg(not(target_arch = "wasm32"))]
pub mod uniffi_bindings;

// Re-export UniFFI types at crate root so scaffolding can find them
#[cfg(not(target_arch = "wasm32"))]
pub use uniffi_bindings::{
    // Crypto Core
    ClassicCryptoCore,
    CryptoError,
    EncryptedMessageComponents,
    RegistrationBundleJson,
    SessionInitResult,
    PrivateKeysJson,
    create_crypto_core,
    create_crypto_core_from_keys_json,
    // Traffic Protection
    TrafficProtectionManager,
    CoverTrafficConfig,
    EnergyMetrics,
    TimingConfig,
    generate_dummy_message,
    is_dummy_message,
    jittered_interval_ms,
    random_send_delay_ms,
    heartbeat_interval_ms,
    battery_aware_jitter_ms,
    recommended_send_delay_ms,
};

// Include UniFFI scaffolding generated from construct_core.udl
#[cfg(not(target_arch = "wasm32"))]
uniffi::include_scaffolding!("construct_core");

// Модули
pub mod api;
pub mod config;
pub mod crypto;
pub mod protocol;
pub mod storage;
pub mod state;
pub mod utils;
pub mod error;

// Traffic Protection (Padding, Cover Traffic, Timing Jitter)
// Implementation of TRAFFIC_PROTECTION_IMPLEMENTATION_PLAN.md (no Sealed Sender)
pub mod traffic_protection;

// Re-exports для удобства
pub use api::MessengerAPI;

