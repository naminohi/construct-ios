//! Cover traffic generation
//!
//! Generates dummy messages to hide real communication patterns.
//!
//! ## Energy Efficiency (Battery-First Design)
//!
//! - Battery-aware: auto-disable when battery < 20%
//! - Network coalescing: piggyback on real messages
//! - Adaptive intervals: increase when idle
//! - Minimal wake-ups: use existing network windows

use rand::RngCore;
use serde::{Deserialize, Serialize};

/// Marker bytes for dummy messages (server ignores these)
const DUMMY_MARKER: &[u8] = b"__CONSTRUCT_DUMMY__";

/// Dummy message payload
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DummyMessage {
    /// Marker to identify as dummy
    marker: String,

    /// Random padding
    #[serde(with = "serde_bytes")]
    padding: Vec<u8>,
}

/// Generate a dummy message that looks like real traffic
///
/// # Arguments
/// * `size` - Target size in bytes (will pad to this size)
///
/// # Returns
/// Serialized dummy message bytes
///
/// # Energy Efficiency
/// - Pre-allocated buffer
/// - Single RNG call
pub fn generate_dummy_message(size: usize) -> Vec<u8> {
    let mut rng = rand::thread_rng();

    let overhead = DUMMY_MARKER.len() + 32; // Approximate serialization overhead
    let padding_size = size.saturating_sub(overhead);

    let mut padding = vec![0u8; padding_size];
    rng.fill_bytes(&mut padding);

    let dummy = DummyMessage {
        marker: String::from_utf8_lossy(DUMMY_MARKER).to_string(),
        padding,
    };

    rmp_serde::to_vec(&dummy).unwrap_or_else(|_| vec![0u8; size])
}

/// Check if a message is a dummy message
///
/// Server should call this and discard dummy messages.
pub fn is_dummy_message(data: &[u8]) -> bool {
    // Try to deserialize
    if let Ok(msg) = rmp_serde::from_slice::<DummyMessage>(data) {
        return msg.marker == String::from_utf8_lossy(DUMMY_MARKER);
    }

    // Fallback: check raw bytes
    if data.len() > DUMMY_MARKER.len() {
        return data.windows(DUMMY_MARKER.len()).any(|w| w == DUMMY_MARKER);
    }

    false
}

/// Configuration for cover traffic generation
#[derive(Debug, Clone)]
pub struct CoverTrafficConfig {
    /// Enable cover traffic
    pub enabled: bool,

    /// Battery level threshold (0.0-1.0, e.g. 0.2 = 20%)
    /// Disable cover traffic when battery below this level
    pub battery_level_threshold: f32,

    /// Minimum interval between dummy messages (ms)
    pub min_interval_ms: u64,

    /// Maximum interval between dummy messages (ms)
    pub max_interval_ms: u64,

    /// Target size for dummy messages (bytes)
    pub message_size: usize,

    /// Coalesce with real messages (send dummy only if no real messages sent recently)
    pub coalesce_with_real_messages: bool,

    /// Coalescing window (ms) - if real message sent within this window, skip dummy
    pub coalesce_window_ms: u64,
}

impl Default for CoverTrafficConfig {
    fn default() -> Self {
        Self {
            enabled: false, // Disabled by default (opt-in for privacy-conscious users)
            battery_level_threshold: 0.2, // 20% - aggressive battery protection
            min_interval_ms: 30000,   // 30 seconds (conservative)
            max_interval_ms: 300000,  // 5 minutes
            message_size: 255,        // Match padding block size
            coalesce_with_real_messages: true, // Energy efficient
            coalesce_window_ms: 10000, // 10 seconds
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_dummy_message_detection() {
        let dummy = generate_dummy_message(256);
        assert!(is_dummy_message(&dummy));

        let real_msg = b"This is a real message";
        assert!(!is_dummy_message(real_msg));
    }

    #[test]
    fn test_dummy_message_size() {
        for size in [128, 256, 512, 1024] {
            let dummy = generate_dummy_message(size);
            // Allow some variance due to serialization
            assert!(dummy.len() >= size / 2 && dummy.len() <= size * 2);
        }
    }
}
