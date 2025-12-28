# Rust-Swift Integration Plan
## План интеграции нового Rust API с Swift-оболочкой

Дата: 27 декабря 2025
Статус: В разработке

---

## 📊 Текущее состояние

### ✅ Что уже работает

**Rust Core:**
- ✅ Новая trait-based архитектура (KeyAgreement + SecureMessaging)
- ✅ X3DH implementation в `crypto/handshake/x3dh.rs`
- ✅ Double Ratchet в `crypto/messaging/double_ratchet.rs`
- ✅ Session API в `crypto/session_api.rs`
- ✅ Client API в `crypto/client_api.rs`
- ✅ Все тесты проходят: 20/20 crypto tests ✅

**Swift интеграция:**
- ✅ UniFFI биндинги работают (`uniffi_bindings.rs`)
- ✅ UDL файл определён (`construct_core.udl`)
- ✅ Swift CryptoManager использует Rust core
- ✅ Работает registration, session init, encrypt/decrypt

### ⚠️ Что нужно обновить

**Rust:**
- ⚠️ `uniffi_bindings.rs` использует старый `CryptoCore` из `api/crypto.rs`
- ⚠️ Старый `api/crypto.rs` не использует новые Session/Client API
- ⚠️ Импорты ссылаются на старые модули (`crypto::double_ratchet`, `crypto::x3dh`)

**Swift:**
- ✅ Swift код уже использует правильный wire format
- ✅ Не требует изменений (только перекомпиляция)

---

## 🎯 Цели интеграции

### 1. Минимальные изменения в Swift
Swift-код уже правильный! Он работает через UniFFI и использует правильный wire format. Мы НЕ меняем:
- ❌ Swift API (CryptoManager methods)
- ❌ Wire format (EncryptedMessageComponents)
- ❌ UDL interface

### 2. Обновить только Rust backend
Мы заменим внутренности `uniffi_bindings.rs` чтобы использовать новый Client API вместо старого CryptoCore:

**До:**
```rust
uniffi_bindings.rs
  └── api/crypto.rs::CryptoCore
        └── old crypto modules
```

**После:**
```rust
uniffi_bindings.rs
  └── crypto/client_api.rs::Client
        └── crypto/session_api.rs::Session
              ├── crypto/handshake/x3dh.rs
              └── crypto/messaging/double_ratchet.rs
```

---

## 📋 План миграции

### Этап 1: Обновить `uniffi_bindings.rs` ✨

**Файл:** `packages/core/src/uniffi_bindings.rs`

**Изменения:**
1. Заменить `CryptoCore<ClassicSuiteProvider>` на `Client<ClassicSuiteProvider, X3DHProtocol, DoubleRatchetSession>`
2. Обновить импорты:
```rust
// OLD
use crate::api::crypto::CryptoCore;
use crate::crypto::suites::classic::ClassicSuiteProvider;

// NEW
use crate::crypto::client_api::ClassicClient;
use crate::crypto::handshake::x3dh::X3DHPublicKeyBundle;
use crate::crypto::messaging::double_ratchet::EncryptedRatchetMessage;
```

3. Обновить методы:
```rust
// OLD: init_session
core.init_session(&contact_id, &internal_bundle)

// NEW: init_session
// Extract remote_identity from bundle
let remote_identity = P::kem_public_key_from_bytes(key_bundle.identity_public.clone());
let public_bundle = X3DHPublicKeyBundle { ... };
client.init_session(&contact_id, &public_bundle, &remote_identity)
```

4. Обновить `init_receiving_session`:
```rust
// OLD:
core.init_receiving_session(&contact_id, &internal_bundle, &encrypted_first_message)

// NEW:
let remote_identity = P::kem_public_key_from_bytes(...);
let remote_ephemeral = P::kem_public_key_from_bytes(first_msg.ephemeral_public_key);
client.init_receiving_session_with_ephemeral(
    &contact_id,
    &remote_identity,
    &remote_ephemeral,
    &encrypted_first_message
)
```

**Критически важно:**
- ✅ Сохранить тот же UDL interface (не менять!)
- ✅ Сохранить wire format (EncryptedMessageComponents)
- ✅ Сохранить error types (CryptoError enum)

### Этап 2: Обновить импорты в других модулях

**Файлы для обновления:**
1. `src/api/crypto.rs` - можно пометить как deprecated
2. `src/state/app.rs` - обновить импорты на новый Client API

### Этап 3: Тестирование

**План тестирования:**
1. ✅ Unit тесты Rust (уже проходят)
2. ⚠️ Собрать Swift bindings: `cargo build && swift build`
3. ⚠️ Тестировать через Swift:
   - Registration bundle generation
   - Session initialization (Alice initiates)
   - Session initialization (Bob receives)
   - Message encryption/decryption
   - Multiple messages back and forth

**Команды:**
```bash
# 1. Build Rust library
cd packages/core
cargo build --release

# 2. Generate UniFFI bindings
cargo run --bin uniffi-bindgen generate src/construct_core.udl --language swift

# 3. Build Swift app
cd ../..
xcodebuild -scheme ConstructMessenger -configuration Debug build

# 4. Run Swift tests
xcodebuild test -scheme ConstructMessenger
```

### Этап 4: Cleanup старого кода (опционально)

После успешной миграции можно:
1. Пометить как deprecated:
   - `src/crypto/client.rs` → deprecated (use `client_api.rs`)
   - `src/crypto/x3dh.rs` → deprecated (use `handshake/x3dh.rs`)
   - `src/crypto/double_ratchet.rs` → deprecated (use `messaging/double_ratchet.rs`)
   - `src/api/crypto.rs` → deprecated (use `client_api.rs`)

2. Добавить миграционные notes:
```rust
#[deprecated(since = "0.2.0", note = "Use crypto::client_api::Client instead")]
pub struct ClientCrypto<P: CryptoProvider> { ... }
```

---

## 🔍 Анализ совместимости

### Wire Format Compatibility ✅

**Текущий формат (Swift → Rust):**
```json
{
  "ephemeral_public_key": [u8; 32],
  "message_number": u32,
  "content": "base64(nonce || ciphertext)"
}
```

**Новый Rust тип:**
```rust
pub struct EncryptedRatchetMessage {
    pub dh_public_key: [u8; 32],      // ✅ same as ephemeral_public_key
    pub message_number: u32,           // ✅ same
    pub ciphertext: Vec<u8>,           // ✅ extracted from content
    pub nonce: Vec<u8>,                // ✅ extracted from content
    pub previous_chain_length: u32,    // ℹ️ не используется в wire format
    pub suite_id: u16,                 // ℹ️ не используется в wire format
}
```

**Вывод:** Полностью совместимо! Просто нужно правильно парсить.

### Session Management Compatibility ✅

**Текущий подход:**
```swift
// Swift хранит mapping: userId -> sessionId
userSessions[userId] = sessionId

// Rust хранит сессии внутри
CryptoCore::sessions: HashMap<String, Session>
```

**Новый подход:**
```rust
Client::sessions: HashMap<String, Session<P, H, M>>
```

**Вывод:** Полностью совместимо! Та же логика, новая реализация.

---

## 🚀 Migration Checklist

### Phase 1: Code Changes
- [ ] Обновить `uniffi_bindings.rs` для использования `Client` вместо `CryptoCore`
- [ ] Обновить `create_crypto_core()` → `create_crypto_client()`
- [ ] Протестировать компиляцию: `cargo build`
- [ ] Запустить Rust тесты: `cargo test`

### Phase 2: UniFFI Bindings
- [ ] Сгенерировать новые Swift bindings: `uniffi-bindgen generate`
- [ ] Проверить что Swift API не изменился
- [ ] Обновить `construct_core.swift` в проекте

### Phase 3: Swift Integration
- [ ] Перекомпилировать Swift проект
- [ ] Запустить Swift unit tests
- [ ] Тестировать registration flow
- [ ] Тестировать messaging flow (Alice → Bob)
- [ ] Тестировать messaging flow (Bob → Alice)
- [ ] Тестировать multiple messages

### Phase 4: Cleanup
- [ ] Пометить старые модули как deprecated
- [ ] Обновить документацию
- [ ] Обновить README с новой архитектурой

---

## 📝 Implementation Notes

### Ключевые отличия в API

**OLD CryptoCore API:**
```rust
impl CryptoCore<P> {
    fn init_session(&mut self, contact_id: &str, remote_bundle: &KeyBundle) -> Result<String>;
    fn encrypt_message(&mut self, session_id: &str, plaintext: &str) -> Result<EncryptedRatchetMessage>;
}
```

**NEW Client API:**
```rust
impl Client<P, H, M> {
    fn init_session(
        &mut self,
        contact_id: &str,
        remote_bundle: &H::PublicKeyBundle,
        remote_identity: &P::KemPublicKey,
    ) -> Result<String>;

    fn encrypt_message(&mut self, contact_id: &str, plaintext: &[u8]) -> Result<M::EncryptedMessage>;
}
```

**Изменения:**
1. ✅ `session_id` → `contact_id` (более понятно)
2. ✅ Добавлен параметр `remote_identity` (явный, не извлекаем из bundle)
3. ✅ Generic типы для extensibility

### Error Handling Strategy

**UniFFI errors остаются прежними:**
```rust
#[derive(Debug, thiserror::Error)]
pub enum CryptoError {
    InitializationFailed,
    SessionInitializationFailed,
    EncryptionFailed,
    DecryptionFailed,
    // ...
}
```

**Внутренняя конвертация:**
```rust
client.init_session(...)
    .map_err(|_| CryptoError::SessionInitializationFailed)
```

---

## 🎓 Next Steps

### Immediate (сегодня):
1. ✅ Создать этот документ
2. ⏳ Обновить `uniffi_bindings.rs`
3. ⏳ Протестировать компиляцию

### Short-term (эта неделя):
1. ⏳ Сгенерировать Swift bindings
2. ⏳ Интеграционное тестирование
3. ⏳ Обновить документацию

### Long-term (следующая итерация):
1. ⏳ Добавить PQ-криптографию
2. ⏳ Hybrid crypto suite
3. ⏳ Расширенное тестирование

---

## 📚 References

- **Rust API Documentation:** `packages/core/src/crypto/`
- **UniFFI Guide:** https://mozilla.github.io/uniffi-rs/
- **Swift Integration:** `ConstructMessenger/Security/CryptoManager.swift`
- **Wire Protocol:** `docs/api/websocket-protocol.md`

---

## ✅ Success Criteria

Миграция считается успешной когда:

1. ✅ Все Rust тесты проходят (20/20 crypto tests)
2. ✅ Swift проект компилируется без ошибок
3. ✅ Все Swift тесты проходят
4. ✅ Registration flow работает
5. ✅ Alice может отправить сообщение Bob
6. ✅ Bob может прочитать сообщение от Alice
7. ✅ Bob может ответить Alice
8. ✅ Multiple messages в обе стороны работают
9. ✅ Out-of-order messages обрабатываются корректно

---

**Автор:** Claude + Maxim
**Последнее обновление:** 27.12.2025
