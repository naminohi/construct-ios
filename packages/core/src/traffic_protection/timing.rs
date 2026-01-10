//! Timing utilities for traffic analysis resistance
//!
//! Provides jittered intervals and delays to prevent timing correlation.
//!
//! ## Energy Efficiency
//!
//! - Minimal CPU wake-ups
//! - Coalesced with network activity
//! - No background threads

use rand::Rng;
use std::time::Duration;

/// Generate a jittered interval
///
/// # Arguments
/// * `base_ms` - Base interval in milliseconds
/// * `jitter_ms` - Maximum random jitter to add
///
/// # Returns
/// Duration with random jitter added
pub fn jittered_interval(base_ms: u64, jitter_ms: u64) -> Duration {
    let jitter = rand::thread_rng().gen_range(0..=jitter_ms);
    Duration::from_millis(base_ms + jitter)
}

/// Generate a random delay before sending a message
///
/// This helps prevent timing correlation between when a message
/// is composed and when it's sent.
///
/// # Arguments
/// * `max_delay_ms` - Maximum delay in milliseconds
///
/// # Returns
/// Random duration between 0 and max_delay_ms
pub fn random_send_delay(max_delay_ms: u64) -> Duration {
    let delay = rand::thread_rng().gen_range(0..=max_delay_ms);
    Duration::from_millis(delay)
}

/// Heartbeat timing with jitter
///
/// # Arguments
/// * `base_interval_sec` - Base heartbeat interval in seconds
///
/// # Returns
/// Jittered interval (±5 seconds)
pub fn heartbeat_interval(base_interval_sec: u64) -> Duration {
    jittered_interval(base_interval_sec * 1000, 5000)
}

/// Configuration for timing behavior
#[derive(Debug, Clone)]
pub struct TimingConfig {
    /// Base heartbeat interval (seconds)
    pub heartbeat_interval_sec: u64,

    /// Heartbeat jitter (milliseconds)
    pub heartbeat_jitter_ms: u64,

    /// Maximum send delay (milliseconds)
    pub max_send_delay_ms: u64,

    /// Enable timing protection
    pub enabled: bool,
}

impl Default for TimingConfig {
    fn default() -> Self {
        Self {
            heartbeat_interval_sec: 30,
            heartbeat_jitter_ms: 5000, // ±5 seconds
            max_send_delay_ms: 100,    // 0-100ms delay
            enabled: true,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_jittered_interval_range() {
        for _ in 0..100 {
            let duration = jittered_interval(1000, 500);
            let ms = duration.as_millis() as u64;
            assert!(ms >= 1000 && ms <= 1500);
        }
    }

    #[test]
    fn test_random_delay_range() {
        for _ in 0..100 {
            let delay = random_send_delay(100);
            assert!(delay.as_millis() <= 100);
        }
    }
}
