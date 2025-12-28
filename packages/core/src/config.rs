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
