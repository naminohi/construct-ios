// Типы сообщений протокола
// Соответствуют спецификации WebSocket API

use serde::{Deserialize, Serialize};

/// Основной тип сообщения для чата (Double Ratchet совместимый)
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ChatMessage {
    /// UUID v4 идентификатор сообщения
    pub id: String,
    /// UUID отправителя
    pub from: String,
    /// UUID получателя
    pub to: String,
    /// X25519 ephemeral public key (32 bytes)
    #[serde(with = "serde_bytes")]
    pub ephemeral_public_key: Vec<u8>,
    /// Номер сообщения в цепочке
    pub message_number: u32,
    /// Зашифрованное содержимое (ChaCha20-Poly1305)
    pub content: String, // Base64 encoded
    /// Unix timestamp в секундах
    pub timestamp: u64,
}

/// Регистрационный bundle с публичными ключами
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RegistrationBundle {
    /// Base64 X25519 identity public key (44 chars)
    pub identity_public: String,
    /// Base64 X25519 signed prekey public (44 chars)
    pub signed_prekey_public: String,
    /// Base64 Ed25519 signature (88 chars)
    pub signature: String,
    /// Base64 Ed25519 verifying key (44 chars)
    pub verifying_key: String,
    /// Suite ID (crypto suite identifier)
    pub suite_id: String,
}

/// Публичная информация о пользователе
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PublicUserInfo {
    pub id: String,
    pub username: String,
}

/// Публичный ключевой bundle пользователя
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PublicKeyBundleData {
    /// UUID пользователя
    pub user_id: String,
    /// Base64 identity public key
    pub identity_public: String,
    /// Base64 signed prekey public
    pub signed_prekey_public: String,
    /// Base64 signature
    pub signature: String,
    /// Base64 verifying key
    pub verifying_key: String,
}

/// Успешная регистрация (ответ сервера)
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RegisterSuccessData {
    pub user_id: String,
    pub username: String,
    pub session_token: String,
    pub expires: i64,
}

/// Успешный вход (ответ сервера)
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LoginSuccessData {
    pub user_id: String,
    pub username: String,
    pub session_token: String,
    pub expires: i64,
}

/// Подтверждение получения сообщения
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AckData {
    /// ID подтвержденного сообщения
    pub message_id: String,
    pub status: String,
}

/// Данные об ошибке
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ErrorData {
    /// Внутренний код ошибки
    pub code: String,
    /// Человекочитаемое сообщение
    pub message: String,
}

// ============================================================================
// Client Message Data Structures
// ============================================================================

/// Данные для регистрации
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RegisterData {
    pub username: String,
    pub password: String,
    pub public_key: String,
}

/// Данные для входа
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LoginData {
    pub username: String,
    pub password: String,
}

/// Данные для подключения с сессией
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ConnectData {
    pub session_token: String,
}

/// Данные для поиска пользователей
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SearchUsersData {
    pub query: String,
}

/// Данные для запроса публичного ключа
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct GetPublicKeyData {
    pub user_id: String,
}

/// Данные для ротации prekey
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RotatePrekeyData {
    pub user_id: String,
    /// Base64-encoded MessagePack of SignedPrekeyUpdate
    pub update: String,
}

/// Данные для выхода
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LogoutData {
    pub session_token: String,
}

/// Типы сообщений WebSocket протокола (клиент -> сервер)
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", content = "payload", rename_all = "camelCase")]
pub enum ClientMessage {
    Register(RegisterData),
    Login(LoginData),
    Connect(ConnectData),
    SearchUsers(SearchUsersData),
    GetPublicKey(GetPublicKeyData),
    SendMessage(ChatMessage),
    RotatePrekey(RotatePrekeyData),
    Logout(LogoutData),
}

// ============================================================================
// Server Message Data Structures
// ============================================================================

/// Данные успешного подключения
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ConnectSuccessData {
    pub user_id: String,
    pub username: String,
}

/// Результаты поиска пользователей
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SearchResultsData {
    pub users: Vec<PublicUserInfo>,
}

/// Типы сообщений от сервера (сервер -> клиент)
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", content = "payload", rename_all = "camelCase")]
pub enum ServerMessage {
    RegisterSuccess(RegisterSuccessData),
    LoginSuccess(LoginSuccessData),
    ConnectSuccess(ConnectSuccessData),
    SessionExpired,
    SearchResults(SearchResultsData),
    PublicKeyBundle(PublicKeyBundleData),
    Message(ChatMessage),
    Ack(AckData),
    KeyRotationSuccess,
    Error(ErrorData),
    LogoutSuccess,
}
