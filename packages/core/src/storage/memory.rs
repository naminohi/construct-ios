// In-memory storage для тестов и non-WASM платформ

use crate::storage::models::*;
use crate::utils::error::Result;
use std::collections::HashMap;

/// In-memory хранилище
pub struct MemoryStorage {
    private_keys: HashMap<String, StoredPrivateKeys>,
    sessions: HashMap<String, StoredSession>,
    contacts: HashMap<String, StoredContact>,
    messages: Vec<StoredMessage>,
    metadata: HashMap<String, StoredAppMetadata>,
}

impl MemoryStorage {
    pub fn new() -> Self {
        Self {
            private_keys: HashMap::new(),
            sessions: HashMap::new(),
            contacts: HashMap::new(),
            messages: Vec::new(),
            metadata: HashMap::new(),
        }
    }

    // === Приватные ключи ===

    pub fn save_private_keys(&mut self, keys: StoredPrivateKeys) -> Result<()> {
        self.private_keys.insert(keys.user_id.clone(), keys);
        Ok(())
    }

    pub fn load_private_keys(&self, user_id: &str) -> Result<Option<StoredPrivateKeys>> {
        Ok(self.private_keys.get(user_id).cloned())
    }

    // === Сессии ===

    pub fn save_session(&mut self, session: StoredSession) -> Result<()> {
        self.sessions.insert(session.session_id.clone(), session);
        Ok(())
    }

    pub fn load_session(&self, session_id: &str) -> Result<Option<StoredSession>> {
        Ok(self.sessions.get(session_id).cloned())
    }

    pub fn load_all_sessions(&self) -> Result<Vec<StoredSession>> {
        Ok(self.sessions.values().cloned().collect())
    }

    pub fn delete_session(&mut self, session_id: &str) -> Result<()> {
        self.sessions.remove(session_id);
        Ok(())
    }

    // === Контакты ===

    pub fn save_contact(&mut self, contact: StoredContact) -> Result<()> {
        self.contacts.insert(contact.id.clone(), contact);
        Ok(())
    }

    pub fn load_contact(&self, contact_id: &str) -> Result<Option<StoredContact>> {
        Ok(self.contacts.get(contact_id).cloned())
    }

    pub fn load_all_contacts(&self) -> Result<Vec<StoredContact>> {
        Ok(self.contacts.values().cloned().collect())
    }

    pub fn delete_contact(&mut self, contact_id: &str) -> Result<()> {
        self.contacts.remove(contact_id);
        Ok(())
    }

    // === Сообщения ===

    pub fn save_message(&mut self, msg: StoredMessage) -> Result<()> {
        self.messages.push(msg);
        Ok(())
    }

    pub fn load_messages_for_conversation(
        &self,
        conversation_id: &str,
        limit: usize,
        offset: usize,
    ) -> Result<Vec<StoredMessage>> {
        let mut messages: Vec<StoredMessage> = self
            .messages
            .iter()
            .filter(|m| m.conversation_id == conversation_id)
            .cloned()
            .collect();

        // Сортировка по timestamp
        messages.sort_by_key(|m| m.timestamp);

        // Пагинация
        let messages = messages
            .into_iter()
            .skip(offset)
            .take(limit)
            .collect();

        Ok(messages)
    }

    pub fn delete_message(&mut self, message_id: &str) -> Result<()> {
        self.messages.retain(|m| m.id != message_id);
        Ok(())
    }

    // === Метаданные ===

    pub fn save_metadata(&mut self, metadata: StoredAppMetadata) -> Result<()> {
        self.metadata.insert(metadata.user_id.clone(), metadata);
        Ok(())
    }

    pub fn load_metadata(&self, user_id: &str) -> Result<Option<StoredAppMetadata>> {
        Ok(self.metadata.get(user_id).cloned())
    }

    // === Утилиты ===

    pub fn clear_all(&mut self) -> Result<()> {
        self.private_keys.clear();
        self.sessions.clear();
        self.contacts.clear();
        self.messages.clear();
        self.metadata.clear();
        Ok(())
    }
}

impl Default for MemoryStorage {
    fn default() -> Self {
        Self::new()
    }
}

// Для совместимости с существующим кодом
pub type KeyStorage = MemoryStorage;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_memory_storage_private_keys() {
        let mut storage = MemoryStorage::new();

        let keys = StoredPrivateKeys {
            user_id: "user1".to_string(),
            encrypted_identity_private: vec![1, 2, 3],
            encrypted_signed_prekey_private: vec![4, 5, 6],
            encrypted_signing_key: vec![7, 8, 9],
            prekey_signature: vec![13, 14, 15],
            salt: vec![10, 11, 12],
            created_at: 12345,
        };

        storage.save_private_keys(keys.clone()).unwrap();
        let loaded = storage.load_private_keys("user1").unwrap();

        assert!(loaded.is_some());
        assert_eq!(loaded.unwrap().user_id, "user1");
    }

    #[test]
    fn test_memory_storage_sessions() {
        let mut storage = MemoryStorage::new();

        let session = StoredSession {
            session_id: "session1".to_string(),
            contact_id: "contact1".to_string(),
            session_data: vec![1, 2, 3],
            last_used: 12345,
            created_at: 12345,
        };

        storage.save_session(session.clone()).unwrap();
        let loaded = storage.load_session("session1").unwrap();

        assert!(loaded.is_some());
        assert_eq!(loaded.unwrap().contact_id, "contact1");
    }

    #[test]
    fn test_memory_storage_messages() {
        let mut storage = MemoryStorage::new();

        let msg1 = StoredMessage {
            id: "msg1".to_string(),
            conversation_id: "conv1".to_string(),
            from: "user1".to_string(),
            to: "user2".to_string(),
            encrypted_content: "AQID".to_string(),
            timestamp: 100,
            status: MessageStatus::Sent,
        };

        let msg2 = StoredMessage {
            id: "msg2".to_string(),
            conversation_id: "conv1".to_string(),
            from: "user2".to_string(),
            to: "user1".to_string(),
            encrypted_content: "BAUG".to_string(),
            timestamp: 200,
            status: MessageStatus::Read,
        };

        storage.save_message(msg1).unwrap();
        storage.save_message(msg2).unwrap();

        let messages = storage
            .load_messages_for_conversation("conv1", 10, 0)
            .unwrap();

        assert_eq!(messages.len(), 2);
        assert_eq!(messages[0].id, "msg1"); // Сортировка по timestamp
        assert_eq!(messages[1].id, "msg2");
    }
}
