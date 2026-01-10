//! Traffic Protection module
//!
//! Implements countermeasures against traffic analysis:
//! - Message padding (hide message length)
//! - Cover traffic (hide communication patterns)
//! - Timing jitter (hide timing patterns)
//!
//! ## Energy Efficiency
//!
//! This module is designed with mobile battery life as a priority:
//! - Padding: Zero overhead (only during encryption/decryption)
//! - Cover traffic: Battery-aware with adaptive intervals
//! - Timing jitter: Minimal CPU wake-ups

pub mod padding;
pub mod cover_traffic;
pub mod timing;

// Re-exports
pub use padding::{pad_message, unpad_message, PaddingError};
pub use cover_traffic::{generate_dummy_message, is_dummy_message, CoverTrafficConfig};
pub use timing::{jittered_interval, random_send_delay, TimingConfig};
