// Криптографический модуль
// X3DH + Double Ratchet + Signal Protocol

pub mod client;
pub mod double_ratchet;
pub mod x3dh;
pub mod keys;
pub mod session;
pub mod master_key;
pub mod crypto_provider; // Added
pub mod classic_suite; // Added

// Post-Quantum modules (conditionally compiled)
#[cfg(feature = "post-quantum")]
pub mod pq_x3dh;
#[cfg(feature = "post-quantum")]
pub mod pq_double_ratchet;

pub use client::ClientCrypto;
pub use double_ratchet::{DoubleRatchetSession, EncryptedRatchetMessage, SerializableSession};
pub use x3dh::{PublicKeyBundle, RegistrationBundle, X3DH};
pub use crypto_provider::CryptoProvider;

pub type SuiteID = u16;

/// Suite ID for the classic suite as per API_V3_SPEC.md
pub const CLASSIC_SUITE_ID: SuiteID = 1;
/// Suite ID for Post-Quantum hybrid suite (reserved)
pub const PQ_HYBRID_SUITE_ID: SuiteID = 2;
