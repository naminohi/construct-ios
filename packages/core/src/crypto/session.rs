// Управление сессиями
// Хранение и управление Double Ratchet сессиями для разных контактов

use crate::crypto::double_ratchet::{DoubleRatchetSession, SerializableSession};
use crate::utils::error::{ConstructError, Result};
use std::collections::HashMap;
use crate::crypto::CryptoProvider;
use std::marker::PhantomData;

/// Метаданные сессии
pub struct SessionMetadata {
    pub session_id: String,
    pub contact_id: String,
    pub created_at: i64,
    pub last_used: i64,
    pub message_count: u64,
}

impl SessionMetadata {
    pub fn new(session_id: String, contact_id: String) -> Self {
        let now = crate::utils::time::current_timestamp();
        Self {
            session_id,
            contact_id,
            created_at: now,
            last_used: now,
            message_count: 0,
        }
    }

    pub fn update_last_used(&mut self) {
        self.last_used = crate::utils::time::current_timestamp();
        self.message_count += 1;
    }
}

/// Хранилище сессий
pub struct SessionStore<P: CryptoProvider> {
    pub session: DoubleRatchetSession<P>,
    pub metadata: SessionMetadata,
}

/// Менеджер Double Ratchet сессий
pub struct SessionManager<P: CryptoProvider> {
    /// Активные сессии, индексированные по contact_id
    sessions: HashMap<String, SessionStore<P>>,

    /// Максимальное количество сохраненных сессий
    max_sessions: usize,

    _phantom: PhantomData<P>,
}

impl<P: CryptoProvider> SessionManager<P> {
    /// Создать новый SessionManager
    pub fn new() -> Self {
        Self {
            sessions: HashMap::new(),
            max_sessions: 100,
            _phantom: PhantomData,
        }
    }

    /// Создать с заданным лимитом сессий
    pub fn with_capacity(max_sessions: usize) -> Self {
        Self {
            sessions: HashMap::new(),
            max_sessions,
            _phantom: PhantomData,
        }
    }

    /// Добавить новую сессию
    pub fn add_session(&mut self, contact_id: String, session: DoubleRatchetSession<P>) -> Result<()> {
        // Проверяем лимит сессий
        if self.sessions.len() >= self.max_sessions {
            self.cleanup_old_sessions()?;
        }

        let session_id = session.session_id().to_string();
        let metadata = SessionMetadata::new(session_id, contact_id.clone());

        self.sessions.insert(
            contact_id,
            SessionStore {
                session,
                metadata,
            },
        );

        Ok(())
    }

    /// Получить сессию по contact_id
    pub fn get_session(&self, contact_id: &str) -> Option<&DoubleRatchetSession<P>> {
        self.sessions.get(contact_id).map(|store| &store.session)
    }

    /// Получить изменяемую сессию по contact_id
    pub fn get_session_mut(&mut self, contact_id: &str) -> Option<&mut DoubleRatchetSession<P>> {
        self.sessions.get_mut(contact_id).map(|store| {
            store.metadata.update_last_used();
            &mut store.session
        })
    }

    /// Проверить наличие сессии
    pub fn has_session(&self, contact_id: &str) -> bool {
        self.sessions.contains_key(contact_id)
    }

    /// Удалить сессию
    pub fn remove_session(&mut self, contact_id: &str) -> Option<DoubleRatchetSession<P>> {
        self.sessions.remove(contact_id).map(|store| store.session)
    }

    /// Получить метаданные сессии
    pub fn get_metadata(&self, contact_id: &str) -> Option<&SessionMetadata> {
        self.sessions.get(contact_id).map(|store| &store.metadata)
    }

    /// Получить список всех contact_id с активными сессиями
    pub fn get_active_contacts(&self) -> Vec<String> {
        self.sessions.keys().cloned().collect()
    }

    /// Количество активных сессий
    pub fn session_count(&self) -> usize {
        self.sessions.len()
    }

    /// Очистка старых неиспользуемых сессий
    fn cleanup_old_sessions(&mut self) -> Result<()> {
        // Находим самую старую неиспользуемую сессию
        let oldest = self
            .sessions
            .iter()
            .min_by_key(|(_, store)| store.metadata.last_used)
            .map(|(contact_id, _)| contact_id.clone());

        if let Some(contact_id) = oldest {
            self.sessions.remove(&contact_id);
        }

        Ok(())
    }

    /// Очистка всех сессий старше определенного времени
    pub fn cleanup_sessions_older_than(&mut self, max_age_seconds: i64) {
        let now = crate::utils::time::current_timestamp();
        self.sessions
            .retain(|_, store| now - store.metadata.last_used < max_age_seconds);
    }

    /// Сериализовать сессию для сохранения
    pub fn serialize_session(&self, contact_id: &str) -> Result<Vec<u8>> {
        let session = self
            .get_session(contact_id)
            .ok_or_else(|| ConstructError::SessionError(format!("Session not found: {}", contact_id)))?;

        let serializable = session.to_serializable();
        bincode::serialize(&serializable)
            .map_err(|e| ConstructError::SerializationError(format!("Failed to serialize session: {}", e)))
    }

    /// Десериализовать и восстановить сессию
    pub fn deserialize_session(&mut self, contact_id: String, data: &[u8]) -> Result<()> {
        let serializable: SerializableSession = bincode::deserialize(data)
            .map_err(|e| ConstructError::SerializationError(format!("Failed to deserialize session: {}", e)))?;

        let session = DoubleRatchetSession::<P>::from_serializable(serializable)
            .map_err(|e| ConstructError::CryptoError(format!("Failed to restore session: {}", e)))?;
        self.add_session(contact_id, session)?;

        Ok(())
    }

    /// Экспорт всех сессий в формат для сохранения
    pub fn export_all_sessions(&self) -> Result<HashMap<String, Vec<u8>>> {
        let mut exported = HashMap::new();

        for (contact_id, store) in &self.sessions {
            let serializable = store.session.to_serializable();
            let data = bincode::serialize(&serializable)
                .map_err(|e| ConstructError::SerializationError(format!("Failed to serialize session: {}", e)))?;
            exported.insert(contact_id.clone(), data);
        }

        Ok(exported)
    }

    /// Импорт всех сессий
    pub fn import_all_sessions(&mut self, sessions: HashMap<String, Vec<u8>>) -> Result<()> {
        for (contact_id, data) in sessions {
            self.deserialize_session(contact_id, &data)?;
        }

        Ok(())
    }

    /// Очистить все сессии
    pub fn clear_all(&mut self) {
        self.sessions.clear();
    }
}

impl<P: CryptoProvider> Default for SessionManager<P> {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::crypto::classic_suite::ClassicSuiteProvider;
    use x25519_dalek::{PublicKey, StaticSecret};

    #[test]
    fn test_session_manager_add_get() {
        let mut manager = SessionManager::<ClassicSuiteProvider>::new();

        let identity_secret = StaticSecret::random_from_rng(rand::rngs::OsRng);
        let identity_public = PublicKey::from(&identity_secret);
        let root_key = [0u8; 32];

        let session = DoubleRatchetSession::<ClassicSuiteProvider>::new_x3dh_session(
            1,
            &root_key,
            &identity_public.to_bytes().to_vec(),
            &identity_secret.to_bytes().to_vec(),
            "contact1".to_string(),
        )
        .unwrap();

        manager.add_session("contact1".to_string(), session).unwrap();

        assert!(manager.has_session("contact1"));
        assert_eq!(manager.session_count(), 1);
    }

    #[test]
    fn test_session_manager_remove() {
        let mut manager = SessionManager::<ClassicSuiteProvider>::new();

        let identity_secret = StaticSecret::random_from_rng(rand::rngs::OsRng);
        let identity_public = PublicKey::from(&identity_secret);
        let root_key = [0u8; 32];

        let session = DoubleRatchetSession::<ClassicSuiteProvider>::new_x3dh_session(
            1,
            &root_key,
            &identity_public.to_bytes().to_vec(),
            &identity_secret.to_bytes().to_vec(),
            "contact1".to_string(),
        )
        .unwrap();

        manager.add_session("contact1".to_string(), session).unwrap();
        assert!(manager.has_session("contact1"));

        manager.remove_session("contact1");
        assert!(!manager.has_session("contact1"));
    }

    #[test]
    fn test_session_manager_metadata() {
        let mut manager = SessionManager::<ClassicSuiteProvider>::new();

        let identity_secret = StaticSecret::random_from_rng(rand::rngs::OsRng);
        let identity_public = PublicKey::from(&identity_secret);
        let root_key = [0u8; 32];

        let session = DoubleRatchetSession::<ClassicSuiteProvider>::new_x3dh_session(
            1,
            &root_key,
            &identity_public.to_bytes().to_vec(),
            &identity_secret.to_bytes().to_vec(),
            "contact1".to_string(),
        )
        .unwrap();

        manager.add_session("contact1".to_string(), session).unwrap();

        let metadata = manager.get_metadata("contact1").unwrap();
        assert_eq!(metadata.contact_id, "contact1");
        assert_eq!(metadata.message_count, 0);
    }
}