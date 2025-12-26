// Состояние бесед

use crate::storage::models::{MessageStatus, StoredMessage};
use std::collections::HashMap;

/// Состояние одной беседы
#[derive(Debug, Clone)]
pub struct ConversationState {
    pub contact_id: String,
    pub messages: Vec<StoredMessage>,
    pub unread_count: u32,
    pub is_typing: bool,
    pub last_read_message_id: Option<String>,
}

impl ConversationState {
    pub fn new(contact_id: String) -> Self {
        Self {
            contact_id,
            messages: Vec::new(),
            unread_count: 0,
            is_typing: false,
            last_read_message_id: None,
        }
    }

    /// Добавить сообщение в беседу
    pub fn add_message(&mut self, msg: StoredMessage) {
        self.messages.push(msg);
        // Сортировка по timestamp для поддержания порядка
        self.messages.sort_by_key(|m| m.timestamp);
    }

    /// Обновить статус сообщения
    pub fn update_message_status(&mut self, message_id: &str, status: MessageStatus) {
        if let Some(msg) = self.messages.iter_mut().find(|m| m.id == message_id) {
            msg.status = status;
        }
    }

    /// Отметить сообщения как прочитанные
    pub fn mark_as_read(&mut self, message_id: String) {
        self.last_read_message_id = Some(message_id);
        self.unread_count = 0;

        // Обновить статусы всех сообщений до указанного
        for msg in &mut self.messages {
            if msg.status == MessageStatus::Delivered {
                msg.status = MessageStatus::Read;
            }
        }
    }

    /// Увеличить счетчик непрочитанных
    pub fn increment_unread(&mut self) {
        self.unread_count += 1;
    }

    /// Установить статус "печатает"
    pub fn set_typing(&mut self, is_typing: bool) {
        self.is_typing = is_typing;
    }

    /// Получить последнее сообщение
    pub fn get_last_message(&self) -> Option<&StoredMessage> {
        self.messages.last()
    }

    /// Получить количество сообщений
    pub fn message_count(&self) -> usize {
        self.messages.len()
    }

    /// Очистить все сообщения
    pub fn clear_messages(&mut self) {
        self.messages.clear();
        self.unread_count = 0;
        self.last_read_message_id = None;
    }
}

/// Менеджер всех бесед
#[derive(Debug)]
pub struct ConversationsManager {
    conversations: HashMap<String, ConversationState>,
}

impl ConversationsManager {
    pub fn new() -> Self {
        Self {
            conversations: HashMap::new(),
        }
    }

    /// Получить или создать беседу
    pub fn get_or_create(&mut self, contact_id: &str) -> &mut ConversationState {
        self.conversations
            .entry(contact_id.to_string())
            .or_insert_with(|| ConversationState::new(contact_id.to_string()))
    }

    /// Получить беседу
    pub fn get(&self, contact_id: &str) -> Option<&ConversationState> {
        self.conversations.get(contact_id)
    }

    /// Получить изменяемую беседу
    pub fn get_mut(&mut self, contact_id: &str) -> Option<&mut ConversationState> {
        self.conversations.get_mut(contact_id)
    }

    /// Добавить сообщение в беседу
    pub fn add_message(&mut self, contact_id: &str, msg: StoredMessage) {
        let conversation = self.get_or_create(contact_id);
        conversation.add_message(msg);
    }

    /// Получить список всех бесед
    pub fn get_all_conversations(&self) -> Vec<&ConversationState> {
        self.conversations.values().collect()
    }

    /// Получить список бесед с непрочитанными сообщениями
    pub fn get_unread_conversations(&self) -> Vec<&ConversationState> {
        self.conversations
            .values()
            .filter(|c| c.unread_count > 0)
            .collect()
    }

    /// Получить общее количество непрочитанных сообщений
    pub fn total_unread_count(&self) -> u32 {
        self.conversations.values().map(|c| c.unread_count).sum()
    }

    /// Удалить беседу
    pub fn remove_conversation(&mut self, contact_id: &str) -> Option<ConversationState> {
        self.conversations.remove(contact_id)
    }

    /// Очистить все беседы
    pub fn clear_all(&mut self) {
        self.conversations.clear();
    }

    /// Получить количество бесед
    pub fn conversation_count(&self) -> usize {
        self.conversations.len()
    }
}

impl Default for ConversationsManager {
    fn default() -> Self {
        Self::new()
    }
}

// Для обратной совместимости
pub type ConversationsState = ConversationsManager;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_conversation_state() {
        let mut conv = ConversationState::new("contact1".to_string());

        let msg1 = StoredMessage {
            id: "msg1".to_string(),
            conversation_id: "contact1".to_string(),
            from: "user1".to_string(),
            to: "contact1".to_string(),
            encrypted_content: "AQID".to_string(),
            timestamp: 100,
            status: MessageStatus::Sent,
        };

        conv.add_message(msg1);
        assert_eq!(conv.message_count(), 1);
        assert_eq!(conv.get_last_message().unwrap().id, "msg1");
    }

    #[test]
    fn test_conversations_manager() {
        let mut manager = ConversationsManager::new();

        let msg1 = StoredMessage {
            id: "msg1".to_string(),
            conversation_id: "contact1".to_string(),
            from: "user1".to_string(),
            to: "contact1".to_string(),
            encrypted_content: "AQID".to_string(),
            timestamp: 100,
            status: MessageStatus::Sent,
        };

        manager.add_message("contact1", msg1);

        assert_eq!(manager.conversation_count(), 1);
        assert!(manager.get("contact1").is_some());
    }

    #[test]
    fn test_unread_count() {
        let mut manager = ConversationsManager::new();

        let msg1 = StoredMessage {
            id: "msg1".to_string(),
            conversation_id: "contact1".to_string(),
            from: "contact1".to_string(),
            to: "user1".to_string(),
            encrypted_content: "BAUG".to_string(),
            timestamp: 100,
            status: MessageStatus::Delivered,
        };

        manager.add_message("contact1", msg1);
        manager.get_mut("contact1").unwrap().increment_unread();

        assert_eq!(manager.total_unread_count(), 1);

        manager
            .get_mut("contact1")
            .unwrap()
            .mark_as_read("msg1".to_string());
        assert_eq!(manager.total_unread_count(), 0);
    }
}
