# План рефакторинга криптографической подсистемы

## Цель
Создать чёткую, понятную архитектуру с явным dataflow и разделением ответственности.

## Текущие проблемы
1. **Неясная иерархия**: `ClientCrypto` vs `CryptoCore` - что главнее?
2. **Плохие названия**: `client.rs` не отражает, что это session manager
3. **Спутанность**: Связь между X3DH и Double Ratchet неявная
4. **Dataflow неочевиден** из названий модулей и функций

## Новая архитектура

### Структура каталогов
```
packages/core/src/crypto/
├── mod.rs                      # Публичный API, re-exports
├── provider.rs                 # CryptoProvider trait (crypto-agility)
│
├── suites/                     # Криптографические наборы
│   ├── mod.rs
│   └── classic.rs              # X25519 + Ed25519 + ChaCha20-Poly1305
│
├── handshake/                  # Протоколы установки сессии
│   ├── mod.rs                  # KeyAgreement trait
│   └── x3dh.rs                 # X3DH implementation
│
├── messaging/                  # Протоколы обмена сообщениями
│   ├── mod.rs                  # SecureMessaging trait
│   └── double_ratchet.rs       # Double Ratchet implementation
│
├── session.rs                  # Session<P> - объединение handshake + messaging
├── client.rs                   # Client<P> - высокоуровневый API для приложения
└── keys.rs                     # KeyManager (существующий)
```

### Trait hierarchy

```rust
// packages/core/src/crypto/handshake/mod.rs

/// Протокол установки ключей (key agreement)
pub trait KeyAgreement<P: CryptoProvider> {
    /// Регистрационные данные для сервера
    type RegistrationBundle;

    /// Публичные ключи для обмена
    type PublicKeyBundle;

    /// Результат handshake - общий root key
    type SharedSecret;

    /// Генерация регистрационного bundle
    fn generate_registration_bundle() -> Result<Self::RegistrationBundle, String>;

    /// Инициатор: выполнить handshake (Alice)
    fn perform_as_initiator(
        local_identity: &P::KemPrivateKey,
        remote_bundle: &Self::PublicKeyBundle,
    ) -> Result<(Self::SharedSecret, InitiatorState<P>), String>;

    /// Получатель: выполнить handshake (Bob)
    fn perform_as_responder(
        local_identity: &P::KemPrivateKey,
        local_signed_prekey: &P::KemPrivateKey,
        remote_identity: &P::KemPublicKey,
        remote_ephemeral: &P::KemPublicKey,
    ) -> Result<Self::SharedSecret, String>;
}

/// Состояние инициатора после handshake (ephemeral key)
pub struct InitiatorState<P: CryptoProvider> {
    pub ephemeral_private: P::KemPrivateKey,
}
```

```rust
// packages/core/src/crypto/messaging/mod.rs

/// Протокол защищённого обмена сообщениями
pub trait SecureMessaging<P: CryptoProvider> {
    /// Зашифрованное сообщение в wire format
    type EncryptedMessage;

    /// Создать сессию как инициатор (Alice)
    fn new_initiator_session(
        root_key: &[u8],
        initiator_state: InitiatorState<P>,
        remote_identity: &P::KemPublicKey,
        contact_id: String,
    ) -> Result<Self, String>
    where
        Self: Sized;

    /// Создать сессию как получатель (Bob)
    fn new_responder_session(
        root_key: &[u8],
        local_identity: &P::KemPrivateKey,
        first_message: &Self::EncryptedMessage,
        contact_id: String,
    ) -> Result<Self, String>
    where
        Self: Sized;

    /// Зашифровать сообщение
    fn encrypt(&mut self, plaintext: &[u8]) -> Result<Self::EncryptedMessage, String>;

    /// Расшифровать сообщение
    fn decrypt(&mut self, message: &Self::EncryptedMessage) -> Result<Vec<u8>, String>;
}
```

### Session API

```rust
// packages/core/src/crypto/session.rs

/// Криптографическая сессия с контактом
///
/// Объединяет handshake протокол и messaging протокол
pub struct Session<P, H, M>
where
    P: CryptoProvider,
    H: KeyAgreement<P>,
    M: SecureMessaging<P>,
{
    session_id: String,
    contact_id: String,
    messaging: M,
    _phantom: PhantomData<(P, H)>,
}

impl<P, H, M> Session<P, H, M>
where
    P: CryptoProvider,
    H: KeyAgreement<P>,
    M: SecureMessaging<P>,
{
    /// Создать сессию как инициатор (после X3DH)
    pub fn new_initiator(
        contact_id: String,
        root_key: Vec<u8>,
        initiator_state: InitiatorState<P>,
        remote_identity: P::KemPublicKey,
    ) -> Result<Self, String> {
        let messaging = M::new_initiator_session(
            &root_key,
            initiator_state,
            &remote_identity,
            contact_id.clone(),
        )?;

        Ok(Self {
            session_id: uuid::Uuid::new_v4().to_string(),
            contact_id,
            messaging,
            _phantom: PhantomData,
        })
    }

    /// Создать сессию как получатель (из первого сообщения)
    pub fn new_responder(
        contact_id: String,
        root_key: Vec<u8>,
        local_identity: P::KemPrivateKey,
        first_message: &M::EncryptedMessage,
    ) -> Result<Self, String> {
        let messaging = M::new_responder_session(
            &root_key,
            &local_identity,
            first_message,
            contact_id.clone(),
        )?;

        Ok(Self {
            session_id: uuid::Uuid::new_v4().to_string(),
            contact_id,
            messaging,
            _phantom: PhantomData,
        })
    }

    pub fn encrypt(&mut self, plaintext: &[u8]) -> Result<M::EncryptedMessage, String> {
        self.messaging.encrypt(plaintext)
    }

    pub fn decrypt(&mut self, message: &M::EncryptedMessage) -> Result<Vec<u8>, String> {
        self.messaging.decrypt(message)
    }

    pub fn session_id(&self) -> &str {
        &self.session_id
    }

    pub fn contact_id(&self) -> &str {
        &self.contact_id
    }
}
```

### Client API (высокий уровень)

```rust
// packages/core/src/crypto/client.rs

/// Высокоуровневый клиент для E2E шифрования
///
/// Управляет:
/// - Регистрацией и ключами пользователя
/// - Множественными сессиями с контактами
/// - Handshake протоколом и обменом сообщениями
pub struct Client<P, H, M>
where
    P: CryptoProvider,
    H: KeyAgreement<P>,
    M: SecureMessaging<P>,
{
    // Долгосрочные ключи пользователя
    identity_key: P::KemPrivateKey,
    signed_prekey: P::KemPrivateKey,
    signing_key: P::SignaturePrivateKey,

    // Активные сессии с контактами
    sessions: HashMap<String, Session<P, H, M>>,

    _phantom: PhantomData<(P, H)>,
}

impl<P, H, M> Client<P, H, M>
where
    P: CryptoProvider,
    H: KeyAgreement<P>,
    M: SecureMessaging<P>,
{
    /// Создать нового клиента с новыми ключами
    pub fn new() -> Result<Self, String> { ... }

    /// Экспортировать регистрационный bundle для сервера
    pub fn export_registration_bundle(&self) -> H::RegistrationBundle { ... }

    /// Инициировать сессию с контактом (Alice)
    pub fn initiate_session(
        &mut self,
        contact_id: &str,
        remote_bundle: &H::PublicKeyBundle,
    ) -> Result<String, String> { ... }

    /// Создать receiving сессию из первого сообщения (Bob)
    pub fn receive_session(
        &mut self,
        contact_id: &str,
        remote_bundle: &H::PublicKeyBundle,
        first_message: &M::EncryptedMessage,
    ) -> Result<String, String> { ... }

    /// Зашифровать сообщение
    pub fn encrypt_message(
        &mut self,
        session_id: &str,
        plaintext: &[u8],
    ) -> Result<M::EncryptedMessage, String> { ... }

    /// Расшифровать сообщение
    pub fn decrypt_message(
        &mut self,
        session_id: &str,
        message: &M::EncryptedMessage,
    ) -> Result<Vec<u8>, String> { ... }
}
```

## Dataflow после рефакторинга

### 1. Регистрация
```
User создаёт Client → Client::new()
  → генерирует identity_key, signed_prekey, signing_key

User → Client::export_registration_bundle()
  → H::generate_registration_bundle()
  → RegistrationBundle → Server
```

### 2. Alice инициирует сессию с Bob
```
Alice получает bob_bundle от Server

Alice → Client::initiate_session(bob_id, bob_bundle)
  → H::perform_as_initiator(alice_identity, bob_bundle)
     → X3DH: генерирует ephemeral key
     → X3DH: DH1, DH2, DH3
     → возвращает (root_key, InitiatorState)

  → Session::new_initiator(bob_id, root_key, InitiatorState, bob_identity)
     → M::new_initiator_session()
        → DoubleRatchet: использует ephemeral key как первый DH ratchet key
        → возвращает DoubleRatchetSession
     → возвращает Session

  → сохраняет session в sessions[session_id]
  → возвращает session_id

Alice → Client::encrypt_message(session_id, plaintext)
  → Session::encrypt(plaintext)
     → M::encrypt() → EncryptedMessage
  → возвращает EncryptedMessage → Server → Bob
```

### 3. Bob получает первое сообщение от Alice
```
Bob получает alice_bundle + encrypted_msg от Server

Bob → Client::receive_session(alice_id, alice_bundle, encrypted_msg)
  → извлекает alice_ephemeral_public из encrypted_msg.dh_public_key

  → H::perform_as_responder(bob_identity, bob_signed_prekey,
                             alice_identity, alice_ephemeral)
     → X3DH: DH1, DH2, DH3 (Bob's perspective)
     → возвращает root_key

  → Session::new_responder(alice_id, root_key, bob_identity, encrypted_msg)
     → M::new_responder_session()
        → DoubleRatchet: создаёт receiving session
        → возвращает DoubleRatchetSession
     → возвращает Session

  → сохраняет session в sessions[session_id]
  → возвращает session_id

Bob → Client::decrypt_message(session_id, encrypted_msg)
  → Session::decrypt(encrypted_msg)
     → M::decrypt() → plaintext
  → возвращает plaintext
```

## Преимущества новой архитектуры

1. **Явный dataflow**: Из названий понятно что делает каждый модуль
2. **Разделение ответственности**:
   - `handshake/` - только установка ключей
   - `messaging/` - только обмен сообщениями
   - `session.rs` - объединение handshake + messaging
   - `client.rs` - высокоуровневый API для приложения

3. **Типобезопасность**: Trait'ы гарантируют корректное использование
4. **Расширяемость**: Легко добавить новые handshake (PQ-X3DH) или messaging протоколы
5. **Тестируемость**: Каждый уровень тестируется отдельно

## Этапы миграции

1. ✅ Создать новую структуру каталогов
2. ✅ Создать trait'ы KeyAgreement и SecureMessaging
3. ✅ Рефакторить X3DH в handshake/x3dh.rs
4. ✅ Рефакторить DoubleRatchet в messaging/double_ratchet.rs
5. ✅ Создать новый Session API
6. ✅ Создать новый Client API
7. ✅ Обновить все импорты в api/crypto.rs и uniffi_bindings.rs
8. ✅ Обновить тесты
9. ✅ Удалить старые файлы (старый client.rs)

## Совместимость

Старый API в `api/crypto.rs` остаётся неизменным (для Swift интеграции).
Внутри он будет использовать новый Client API.
