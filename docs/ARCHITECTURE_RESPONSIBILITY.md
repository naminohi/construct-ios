# 🏗️ Architecture & Responsibility Distribution

**Дата:** 26 декабря 2025
**Версия:** 2.0
**Статус:** ✅ Production

---

## 📋 Оглавление

1. [Основной принцип](#основной-принцип)
2. [Распределение ответственности](#распределение-ответственности)
3. [Правила разработки](#правила-разработки)
4. [Анти-паттерны](#анти-паттерны)
5. [Примеры правильной архитектуры](#примеры-правильной-архитектуры)

---

## 🎯 Основной принцип

> **Swift - максимально тонкий клиент, Rust - вся тяжёлая логика**

```
┌─────────────────────────────────────────────────────────┐
│                    Swift Layer                          │
│  ❌ НЕТ бизнес-логики                                   │
│  ❌ НЕТ криптографии                                    │
│  ❌ НЕТ MessagePack                                     │
│  ✅ ТОЛЬКО UI + передача данных                         │
└───────────────────────┬─────────────────────────────────┘
                        │ UniFFI (тонкая граница)
┌───────────────────────▼─────────────────────────────────┐
│                    Rust Core                            │
│  ✅ ВСЯ криптография (Double Ratchet, X3DH)            │
│  ✅ ВСЯ сериализация (MessagePack)                      │
│  ✅ ВСЯ бизнес-логика (session management)             │
│  ✅ ВСЯ валидация данных                               │
└─────────────────────────────────────────────────────────┘
```

**Философия:**
Swift = черный ящик (просто вход/выход)
Rust = силовая установка (90% логики)

---

## 🧩 Распределение ответственности

### 1️⃣ Swift Layer (iOS/macOS App)

**Файлы:**
- `ConstructMessenger/Security/CryptoManager.swift`
- `ConstructMessenger/ViewModels/*.swift`
- `ConstructMessenger/Views/*.swift`
- `ConstructMessenger/Models/*.swift`

#### ✅ ЧТО Swift ДОЛЖЕН делать:

| Категория | Детали |
|-----------|--------|
| **UI** | SwiftUI views, navigation, user interactions |
| **Core Data** | Локальное хранилище (messages, chats, contacts) |
| **WebSocket** | Соединение с сервером (WebSocketManager) |
| **Передача данных** | Получить от UI → вызвать Rust → отобразить результат |
| **Thin wrapper** | Простые вызовы `core.encryptMessage(...)` без обработки |
| **State management** | @Published свойства для UI reactivity |

#### ❌ ЧТО Swift НЕ должен делать:

| Категория | Причина запрета |
|-----------|-----------------|
| **Криптография** | Только Rust (memory safety, security audit) |
| **MessagePack** | Только Rust (performance, единая точка истины) |
| **Валидация** | Только Rust (защита от tampering) |
| **Бизнес-логика** | Только Rust (переиспользование на Android/Web) |
| **Ручное управление памятью** | UniFFI автоматически управляет Arc<T> |

#### 📝 Пример правильного Swift кода:

```swift
// ✅ ХОРОШО: Thin wrapper
func encryptMessage(_ message: String, for userId: String) throws -> EncryptedMessageComponents {
    guard let core = core else { throw CryptoManagerError.coreNotInitialized }
    guard let sessionId = userSessions[userId] else { throw CryptoManagerError.sessionNotFound }

    // ✅ Rust делает ВСЁ: шифрование, MessagePack, Double Ratchet
    return try core.encryptMessage(sessionId: sessionId, plaintext: message)
}

// ❌ ПЛОХО: Дублирование логики
func encryptMessage(_ message: String, for userId: String) throws -> EncryptedMessageComponents {
    // ❌ НЕ ДЕЛАЙ ЭТО В SWIFT!
    let messageData = try MessagePackEncoder().encode(message) // Wrong!
    let encrypted = try someSwiftCrypto.encrypt(messageData)   // Wrong!
    return encrypted
}
```

---

### 2️⃣ UniFFI Bridge Layer

**Файлы:**
- `packages/core/src/uniffi_bindings.rs`
- `packages/core/src/construct_core.udl`
- `ConstructMessenger/construct_core.swift` (auto-generated)
- `ConstructMessenger/construct_coreFFI.h` (auto-generated)

#### ✅ ЧТО UniFFI делает:

- ✅ Автоматический marshalling (String ↔ RustString, Vec<u8> ↔ RustBuffer)
- ✅ Управление памятью (Arc<T>, drop handling)
- ✅ Error propagation (CryptoError → Swift throws)
- ✅ Type safety (проверка типов на compile time)

#### ❌ ЧТО UniFFI НЕ делает:

- ❌ Бизнес-логика (только маршаллинг)
- ❌ Валидация данных (делается в Rust)

#### 📝 Пример UDL интерфейса:

```idl
// ✅ ХОРОШО: Чистый интерфейс без логики
interface ClassicCryptoCore {
    [Throws=CryptoError]
    EncryptedMessageComponents encrypt_message(string session_id, string plaintext);

    [Throws=CryptoError]
    string decrypt_message(string session_id, sequence<u8> ephemeral_public_key,
                          u32 message_number, string content);
};

// ❌ ПЛОХО: Возврат сырых байтов (требует обработки в Swift)
[Throws=CryptoError]
sequence<u8> encrypt_message_raw(string session_id, sequence<u8> data);
```

---

### 3️⃣ Rust Core (криптографическое ядро)

**Файлы:**
- `packages/core/src/uniffi_bindings.rs` - UniFFI wrapper
- `packages/core/src/api/crypto.rs` - High-level API
- `packages/core/src/crypto/client.rs` - Session management
- `packages/core/src/crypto/double_ratchet.rs` - Double Ratchet Protocol
- `packages/core/src/crypto/x3dh.rs` - X3DH key agreement
- `packages/core/src/crypto/classic_suite.rs` - Криптографические примитивы
- `packages/core/src/crypto/crypto_provider.rs` - Crypto-agility trait

#### ✅ ЧТО Rust делает:

| Категория | Детали |
|-----------|--------|
| **Криптография** | X25519, Ed25519, ChaCha20-Poly1305, HKDF |
| **Протоколы** | Double Ratchet, X3DH, Session management |
| **Сериализация** | MessagePack encode/decode |
| **Валидация** | Проверка подписей, длин ключей, nonce |
| **Memory safety** | 0 unsafe blocks, automatic zeroization |
| **Error handling** | CryptoError enum с детальными сообщениями |
| **Session state** | HashMap<SessionId, DoubleRatchetSession> |

#### 📝 Пример Rust кода:

```rust
// ✅ ХОРОШО: Вся логика в Rust
pub fn encrypt_message(&self, session_id: String, plaintext: String)
    -> Result<EncryptedMessageComponents, CryptoError> {
    let mut core = self.inner.lock().unwrap();

    // 1. Double Ratchet encryption
    let encrypted_message = core.encrypt_message(&session_id, &plaintext)?;

    // 2. Создание sealed box (nonce || ciphertext)
    let mut sealed_box = Vec::new();
    sealed_box.extend_from_slice(&encrypted_message.nonce);
    sealed_box.extend_from_slice(&encrypted_message.ciphertext);

    // 3. Base64 encoding
    let content = base64::engine::general_purpose::STANDARD.encode(&sealed_box);

    // 4. Возврат wire format components
    Ok(EncryptedMessageComponents {
        ephemeral_public_key: encrypted_message.dh_public_key.to_vec(),
        message_number: encrypted_message.message_number,
        content,
    })
}

// ❌ ПЛОХО: Делегирование логики в Swift
pub fn encrypt_message_partial(&self, plaintext: String) -> Result<Vec<u8>, CryptoError> {
    // ❌ НЕ ДЕЛАЙ ЭТО - возвращаешь сырые байты, Swift придется обрабатывать
    Ok(plaintext.as_bytes().to_vec())
}
```

---

## 📜 Правила разработки

### Rule #1: **One Source of Truth**

**Каждая операция должна выполняться ТОЛЬКО в одном месте.**

❌ **ПЛОХО:**
```
Swift: MessagePack encode
  ↓
Rust: MessagePack decode → encrypt → MessagePack encode
  ↓
Swift: MessagePack decode
```

✅ **ХОРОШО:**
```
Swift: plaintext String
  ↓
Rust: encrypt → MessagePack → Base64 → wire format
  ↓
Swift: wire format (готово к отправке)
```

---

### Rule #2: **Zero Logic in Swift**

Swift должен быть **stateless pipe** между UI и Rust.

❌ **ПЛОХО:**
```swift
// ❌ Валидация в Swift
func sendMessage(_ text: String) {
    if text.isEmpty { return }
    if text.count > 10000 { return }
    // Rust вызов
}
```

✅ **ХОРОШО:**
```swift
// ✅ Rust валидирует и возвращает ошибку
func sendMessage(_ text: String) throws {
    try core.encryptMessage(sessionId: sessionId, plaintext: text)
    // Rust проверит всё: emptiness, length, session validity
}
```

---

### Rule #3: **Error Handling Ownership**

- ✅ Rust создает детальные ошибки (`CryptoError`)
- ✅ Swift просто пробрасывает или показывает user-friendly сообщение

❌ **ПЛОХО:**
```swift
// ❌ Swift анализирует ошибки Rust
catch let error as CryptoError {
    if error == .InvalidKeyData {
        // Re-generate keys?
    }
}
```

✅ **ХОРОШО:**
```swift
// ✅ Swift просто показывает ошибку
catch let error as CryptoError {
    errorMessage = error.localizedDescription
}
```

---

### Rule #4: **Performance-Critical Code in Rust**

Любые performance-sensitive операции → Rust.

❌ **ПЛОХО:** 1000 сообщений → 1000 вызовов UniFFI
✅ **ХОРОШО:** Batch API в Rust (один вызов)

---

## 🚫 Анти-паттерны

### Anti-Pattern #1: **Дублирование сериализации**

**Было (ПЛОХО):**
```swift
// Swift
let messageData = try MessagePackEncoder().encode(message)
let encrypted = try core.encrypt(messageData)

// Rust
let decrypted = decrypt(ciphertext)?;
let message: Message = rmp_serde::from_slice(&decrypted)?;
```

**Стало (ХОРОШО):**
```swift
// Swift (zero serialization)
let components = try core.encryptMessage(sessionId: id, plaintext: text)

// Rust (all serialization)
pub fn encrypt_message(...) -> EncryptedMessageComponents {
    // MessagePack, encryption, Base64 - всё в Rust
}
```

---

### Anti-Pattern #2: **Бизнес-логика в Swift**

**Было (ПЛОХО):**
```swift
// ❌ Swift решает, когда ratchet
func shouldRatchet() -> Bool {
    return messageCount % 100 == 0
}
```

**Стало (ХОРОШО):**
```rust
// ✅ Rust автоматически ratchet при необходимости
impl DoubleRatchetSession {
    pub fn encrypt(&mut self, plaintext: &str) -> Result<EncryptedMessage> {
        // Internal ratchet logic
    }
}
```

---

### Anti-Pattern #3: **Ручное управление памятью**

**Было (ПЛОХО):**
```rust
impl Drop for ClassicCryptoCore {
    fn drop(&mut self) {
        // ❌ Ручная очистка → double-free
    }
}
```

**Стало (ХОРОШО):**
```rust
// ✅ UniFFI Arc<T> автоматически управляет памятью
pub struct ClassicCryptoCore {
    inner: Mutex<CryptoCore<ClassicSuiteProvider>>,
}
// No manual Drop needed!
```

---

## 📚 Примеры правильной архитектуры

### Пример 1: Шифрование сообщения

**Swift (тонкая обертка):**
```swift
func encryptMessage(_ message: String, for userId: String) throws -> EncryptedMessageComponents {
    guard let core = core else { throw CryptoManagerError.coreNotInitialized }
    guard let sessionId = userSessions[userId] else { throw CryptoManagerError.sessionNotFound }

    // ✅ Один вызов Rust - вся логика внутри
    return try core.encryptMessage(sessionId: sessionId, plaintext: message)
}
```

**Rust (вся логика):**
```rust
pub fn encrypt_message(&self, session_id: String, plaintext: String)
    -> Result<EncryptedMessageComponents, CryptoError> {
    let mut core = self.inner.lock().unwrap();

    // 1. Валидация
    if plaintext.is_empty() {
        return Err(CryptoError::InvalidInput);
    }

    // 2. Double Ratchet
    let encrypted = core.encrypt_message(&session_id, &plaintext)?;

    // 3. Сериализация (nonce || ciphertext)
    let sealed_box = [&encrypted.nonce[..], &encrypted.ciphertext[..]].concat();

    // 4. Base64
    let content = base64::engine::general_purpose::STANDARD.encode(&sealed_box);

    // 5. Wire format
    Ok(EncryptedMessageComponents {
        ephemeral_public_key: encrypted.dh_public_key.to_vec(),
        message_number: encrypted.message_number,
        content,
    })
}
```

---

### Пример 2: Инициализация сессии

**Swift (просто передача данных):**
```swift
func initializeSession(for userId: String, recipientBundle: (identityPublic: String, ...)) throws {
    guard let core = core else { throw CryptoManagerError.coreNotInitialized }

    // ✅ Rust валидирует bundle, выполняет X3DH, создает Double Ratchet
    let sessionId = try core.initSession(
        contactId: userId,
        recipientBundle: /* MessagePack bundle */
    )

    userSessions[userId] = sessionId
}
```

**Rust (вся X3DH + Double Ratchet логика):**
```rust
pub fn init_session(&mut self, contact_id: String, recipient_bundle: Vec<u8>)
    -> Result<String, CryptoError> {
    // 1. Parse bundle
    let bundle: BundleData = rmp_serde::from_slice(&recipient_bundle)?;

    // 2. Verify signature
    verify_bundle_signature(&bundle)?;

    // 3. X3DH key agreement
    let (shared_secret, ephemeral_public) = perform_x3dh(&bundle, &self.identity_key)?;

    // 4. Create Double Ratchet session
    let session = DoubleRatchetSession::new_x3dh_session(shared_secret, ...)?;

    // 5. Store session
    let session_id = Uuid::new_v4().to_string();
    self.sessions.insert(session_id.clone(), session);

    Ok(session_id)
}
```

---

## 🎓 Checklist для code review

При добавлении нового функционала, проверьте:

- [ ] ✅ Вся криптография в Rust?
- [ ] ✅ Вся сериализация (MessagePack) в Rust?
- [ ] ✅ Валидация данных в Rust?
- [ ] ✅ Swift только передает данные (String, Data)?
- [ ] ✅ Нет дублирования логики между слоями?
- [ ] ✅ Нет ручного управления памятью в Rust (UniFFI Arc<T>)?
- [ ] ✅ Error handling в Rust, Swift только показывает?
- [ ] ✅ Performance-critical код в Rust?

---

## 📄 Связанные документы

- [RUST_SWIFT_INTEGRATION.md](./RUST_SWIFT_INTEGRATION.md) - Подробное руководство по интеграции
- [ROADMAP.md](./ROADMAP.md) - План развития архитектуры
- [README.md](../README.md) - Обзор проекта

---

## 🔄 История изменений

| Версия | Дата | Изменения |
|--------|------|-----------|
| 2.0 | 26.12.2025 | Полная переработка - фокус на распределение ответственности |
| 1.0 | 19.12.2025 | Первая версия (отладка memory errors) |

---

**Последнее обновление:** 26 декабря 2025
**Статус:** ✅ Production-ready architecture principle
**Мейнтейнер:** Maxim Eliseyev
