pub const MAX_SKIPPED_MESSAGES: u32 = 1000;
pub const MAX_SKIPPED_MESSAGE_AGE_SECONDS: i64 = 7 * 24 * 60 * 60; // 7 days

pub struct Config {
    pub server_address: String,
    pub port: u16,
}

impl Config {
    pub fn new(server_address: String, port: u16) -> Self {
        Config {
            server_address,
            port,
        }
    }
}