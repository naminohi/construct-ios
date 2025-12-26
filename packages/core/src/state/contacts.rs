// Состояние контактов


pub struct ContactsState;

impl ContactsState {
    pub fn new() -> Self {
        Self
    }
}

impl Default for ContactsState {
    fn default() -> Self {
        Self::new()
    }
}
