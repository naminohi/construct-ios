# Диагностика проблем с сессиями
**Дата**: 27.12.2025
**Статус**: 🔴 CRITICAL - расшифровка не работает

---

## Анализ логов

### Последовательность событий из логов

```
1. Received: publicKeyBundle(userId: "2a358958-c13a-442d-a9fd-3166d7d4e3ac", username: "alice"...)

2. 🔑 Received public key bundle for 2a358958... - initializing receiving session

3. [UniFFI] init_receiving_session called for contact: 2a358958...

4. [UniFFI] recipient_bundle length: 669 bytes

5. [UniFFI] first_message length: 218 bytes

6. [X3DH] perform_x3dh called

7. [X3DH] Signature verified successfully

8. [X3DH] perform_x3dh completed successfully

9. [ClassicSuite] kem_decapsulate called (TWICE)  ⚠️

10. ✅ Receiving session initialized for user: 2a358958...

11. ✅ Receiving session initialized for 2a358958...

12. 📦 Decrypting: ephemKey=32 bytes, msgNum=0, content=MCjEIt/HWOi8cAjhludB...

13. [DoubleRatchet] decrypt: msgNum=0, current_recv_chain_len=0, skipped_keys=0

14. [DoubleRatchet] decrypt_with_key: msgNum=0, nonce_len=12, ciphertext_len=19

15. [ClassicSuite] aead_decrypt: key_len=32, nonce_len=12, ciphertext_len=19

16. [DoubleRatchet] ❌ Decryption failed

17. [ClientCrypto] ❌ session.decrypt failed: Err("Decryption failed: AEAD decryption failed: aead::Error")

18. ❌ Decryption failed: DecryptionFailed(message: "Decryption failed")

19. ❌ Failed to decrypt first message after session init

20. Updated username for user: alice

21. 📦 Received public key bundle as RESPONDER - waiting for first message to initialize session  ⚠️

22. Session already exists for user: 2a358958...  ⚠️
```

---

## Проблемы, выявленные из логов

### 🔴 Проблема #1: Двойная обработка PublicKeyBundle

**Доказательства**:
- Строка 2: ChatsViewModel обрабатывает publicKeyBundle
- Строка 21: ChatViewModel ТОЖЕ обрабатывает publicKeyBundle

**Код**:

**ChatsViewModel.swift (lines 92-93)**:
```swift
case .publicKeyBundle(let data):
    handlePublicKeyBundle(data)  // ✅ Правильно для responder
```

**ChatViewModel.swift (lines 168)**:
```swift
case .publicKeyBundle(let data):
    if data.userId == chat.otherUser?.id {
        // ... обработка ...  // ❌ НЕ НУЖНО для responder!
    }
```

**Последствия**:
- Оба ViewModel подписаны на `wsManager.messagePublisher`
- Оба получают КАЖДОЕ сообщение
- Дублирование логики обработки
- Потенциальные race conditions

**Решение**: ChatViewModel НЕ должен обрабатывать .publicKeyBundle если он responder!

---

### 🔴 Проблема #2: kem_decapsulate вызывается дважды

**Доказательства**:
Строка 9 показывает:
```
[ClassicSuite] kem_decapsulate called (TWICE)
```

**Ожидаемое поведение** (из документации):
При `new_receiving_session` kem_decapsulate должен вызываться:
1. Один раз для X3DH handshake (Bob's private ↔ Alice's identity public)
2. Один раз для инициализации Double Ratchet receiving chain

**Фактическое поведение**:
Вызывается больше двух раз!

**Возможные причины**:
1. Дублирование обработки (см. Проблема #1)
2. Неправильная инициализация Double Ratchet
3. Retry логика

**Диагностика**:
Нужно проверить `DoubleRatchetSession::new_receiving_session` - сколько раз он вызывает kem_decapsulate?

---

### 🔴 Проблема #3: Расшифровка fails несмотря на успешную инициализацию

**Доказательства**:
- Строка 10-11: "✅ Receiving session initialized" (дважды!)
- Строка 16: "❌ Decryption failed"

**Анализ**:
```
[DoubleRatchet] decrypt: msgNum=0, current_recv_chain_len=0, skipped_keys=0
```

Это означает:
- `messageNumber = 0` ✅ (первое сообщение)
- `current_recv_chain_len = 0` ✅ (ещё ничего не получали)
- Ключ receiving chain должен быть готов

Но AEAD расшифровка fails!

**Гипотеза**: Ключи Alice и Bob НЕ совпадают

**Почему ключи могут не совпадать?**

1. **Alice (initiator) генерирует** ephemeral DH pair при отправке первого сообщения
2. **Bob (responder) использует** ephemeral DH key ИЗ первого сообщения
3. Если Bob использует ДРУГОЙ ключ → несоответствие!

**Проверка**: Откуда Bob берёт ephemeral key?

---

## Анализ кода: откуда Bob берёт ephemeral key?

### Bob's flow (ChatsViewModel.handlePublicKeyBundle)

```swift
// Line 130-136: Инициализация receiving session
try CryptoManager.shared.initReceivingSession(
    for: data.userId,
    recipientBundle: bundleWithSuite,
    firstMessage: firstMessage  // ✅ Передаётся первое сообщение
)
```

### CryptoManager.initReceivingSession

```swift
// Line 133-193: Метод initReceivingSession
func initReceivingSession(
    for userId: String,
    recipientBundle: (...),
    firstMessage: ChatMessage  // ✅ Принимает ChatMessage
) throws {
    // ...

    // Line 163-168: Создание messageDict
    let messageDict: [String: Any] = [
        "ephemeral_public_key": [UInt8](firstMessage.ephemeralPublicKey),  // ✅
        "message_number": firstMessage.messageNumber,  // ✅
        "content": firstMessage.content  // ✅ Base64 string
    ]

    // Line 178-182: Вызов Rust
    let sessionId = try core.initReceivingSession(
        contactId: userId,
        recipientBundle: bundleBytes,
        firstMessage: messageBytes  // ✅ JSON с ephemeral key
    )
}
```

### Rust uniffi_bindings.rs

```rust
// Line 153-238: initReceivingSession implementation
pub fn init_receiving_session(
    &self,
    contact_id: String,
    recipient_bundle: Vec<u8>,
    first_message: Vec<u8>,  // ✅ Принимает JSON
) -> Result<String, CryptoError> {
    // Line 190-194: Parse первого сообщения
    #[derive(Deserialize)]
    struct FirstMessage {
        ephemeral_public_key: Vec<u8>,  // ✅
        message_number: u32,
        content: String,  // Base64
    }

    let first_msg: FirstMessage = serde_json::from_str(message_str)?;

    // Line 196-206: Decode content
    let sealed_box = base64::decode(&first_msg.content)?;
    let nonce = sealed_box[..12].to_vec();
    let ciphertext = sealed_box[12..].to_vec();

    // Line 209-211: Создание dh_public_key
    let dh_public_key: [u8; 32] = first_msg.ephemeral_public_key
        .try_into()
        .map_err(|_| CryptoError::InvalidKeyData)?;

    // Line 214-221: Создание EncryptedRatchetMessage
    let encrypted_first_message = EncryptedRatchetMessage {
        dh_public_key,  // ✅ Из первого сообщения!
        message_number: first_msg.message_number,
        ciphertext,
        nonce,
        previous_chain_length: 0,
        suite_id: key_bundle.suite_id,
    };

    // Line 232-236: Вызов Rust core
    core.init_receiving_session(
        &contact_id,
        &internal_bundle,
        &encrypted_first_message  // ✅ Передаётся!
    )
}
```

### Rust crypto/api.rs

```rust
// Line 156-167: init_receiving_session wrapper
pub fn init_receiving_session(
    &mut self,
    contact_id: &str,
    remote_bundle: &KeyBundle,
    first_message: &EncryptedRatchetMessage,  // ✅
) -> Result<String> {
    let public_bundle: PublicKeyBundle = remote_bundle.clone().into();
    self.client
        .init_receiving_session(contact_id, &public_bundle, first_message)  // ✅
        .map_err(ConstructError::CryptoError)
}
```

### Rust crypto/client.rs

```rust
// Line 175-210: init_receiving_session в ClientCrypto
pub fn init_receiving_session(
    &mut self,
    contact_id: &str,
    remote_bundle: &PublicKeyBundle,
    first_message: &EncryptedRatchetMessage,  // ✅ Получает первое сообщение!
) -> Result<String, String> {
    // Line 187-195: X3DH handshake
    let root_key = X3DH::<P>::perform_x3dh(
        &self.identity_key,
        &self.signed_prekey,
        &remote_identity_public,
        &remote_signed_prekey_public,
        &remote_bundle.signature,
        &remote_verifying_key,
        remote_bundle.suite_id,
    )?;

    // Line 198-204: Создание Double Ratchet receiving session
    let session = DoubleRatchetSession::<P>::new_receiving_session(
        remote_bundle.suite_id,
        &root_key,
        &self.identity_key,
        first_message,  // ✅ ПЕРЕДАЁТСЯ первое сообщение!
        contact_id.to_string(),
    )?;

    let session_id = utils::uuid::generate_v4();
    self.sessions.insert(session_id.clone(), session);

    Ok(session_id)
}
```

**Промежуточный вывод**: Ephemeral key ПРАВИЛЬНО передаётся из первого сообщения! ✅

---

## Анализ кода: как Alice генерирует ephemeral key?

### Alice's flow при отправке первого сообщения

**ChatViewModel.sendMessage** → **CryptoManager.encryptMessage** → **Rust core.encryptMessage**

### Rust uniffi_bindings.rs

```rust
// Line 241-252: encryptMessage
pub fn encrypt_message(
    &self,
    session_id: String,
    plaintext: String,
) -> Result<EncryptedMessageComponents, CryptoError> {
    let mut core = self.inner.lock().unwrap();
    let encrypted_message = core
        .encrypt_message(&session_id, &plaintext)  // ✅
        .map_err(|_| CryptoError::EncryptionFailed)?;

    // Line 264-266: Создание sealed box
    let mut sealed_box = Vec::new();
    sealed_box.extend_from_slice(&encrypted_message.nonce);
    sealed_box.extend_from_slice(&encrypted_message.ciphertext);

    // Line 268-272: Возврат компонентов
    Ok(EncryptedMessageComponents {
        ephemeral_public_key: encrypted_message.dh_public_key.to_vec(),  // ✅
        message_number: encrypted_message.message_number,
        content: base64::encode(&sealed_box),
    })
}
```

### Rust crypto/api.rs

```rust
// Line 169-178: encrypt_message wrapper
pub fn encrypt_message(
    &mut self,
    session_id: &str,
    plaintext: &str,
) -> Result<EncryptedRatchetMessage> {
    self.client
        .encrypt_ratchet_message(session_id, plaintext.as_bytes())
        .map_err(ConstructError::CryptoError)
}
```

### Rust crypto/client.rs

```rust
// Line 212-220: encrypt_ratchet_message
pub fn encrypt_ratchet_message(
    &mut self,
    session_id: &str,
    plaintext: &[u8]
) -> Result<EncryptedRatchetMessage, String> {
    let session = self.sessions
        .get_mut(session_id)
        .ok_or_else(|| format!("Session not found: {}", session_id))?;

    session.encrypt(plaintext)  // ✅ Вызов Double Ratchet encrypt
}
```

### Rust crypto/double_ratchet.rs - encrypt

```rust
// Нужно проверить: откуда берётся dh_public_key в encrypt()?
```

**TODO**: Прочитать `double_ratchet.rs::encrypt()` чтобы понять, какой именно ключ возвращается

---

## Гипотеза: Несоответствие между Alice's dh_public_key и Bob's использованием

### Сценарий A: Alice (initiator) инициализирует сессию

```rust
DoubleRatchetSession::new_x3dh_session(
    root_key,
    remote_dh_public,  // Bob's identity public key
    local_identity_private  // Alice's identity private key
)
```

Внутри `new_x3dh_session`:
```rust
// 1. DH(alice_priv, bob_pub) → receiving chain
let dh_output = kem_decapsulate(local_identity_private, remote_dh_public)?;
let (new_root_key, receiving_chain) = kdf_rk(&root_key_val, &dh_output)?;

// 2. Generate NEW DH pair for sending
let (dh_private, dh_public) = generate_kem_keys()?;  // ⭐ НОВАЯ ПАРА!

// 3. DH(new_priv, bob_pub) → sending chain
let dh_output2 = kem_decapsulate(&dh_private, remote_dh_public)?;
let (final_root_key, sending_chain) = kdf_rk(&new_root_key, &dh_output2)?;

Ok(Self {
    sending_dh_private: dh_private,  // ⭐ Новый приватный ключ
    sending_dh_public: dh_public,    // ⭐ Новый публичный ключ (ephemeral!)
    sending_chain_key: sending_chain,
    // ...
})
```

Когда Alice вызывает `session.encrypt()`:
```rust
pub fn encrypt(&mut self, plaintext: &[u8]) -> Result<EncryptedRatchetMessage> {
    // ...
    EncryptedRatchetMessage {
        dh_public_key: self.sending_dh_public,  // ⭐ Ephemeral key!
        message_number: self.sending_chain_length,
        ciphertext,
        nonce,
        // ...
    }
}
```

### Сценарий B: Bob (responder) инициализирует receiving session

```rust
DoubleRatchetSession::new_receiving_session(
    suite_id,
    root_key,
    local_identity_private,  // Bob's identity private
    first_message,  // EncryptedRatchetMessage from Alice
    contact_id
)
```

**ВОПРОС**: Что делает `new_receiving_session` с `first_message.dh_public_key`?

**TODO**: Прочитать `double_ratchet.rs::new_receiving_session()`

---

## Следующие шаги диагностики

1. ✅ Проверили передачу ephemeral_public_key - правильно
2. ⏸ **Прочитать `new_receiving_session`** - как он использует first_message.dh_public_key
3. ⏸ **Прочитать `new_x3dh_session`** - как генерируется sending_dh_public
4. ⏸ **Сравнить ключи** - Alice's sending_dh_public == Bob's receiving chain input?
5. ⏸ **Устранить двойную обработку** PublicKeyBundle (Проблема #1)
6. ⏸ **Добавить детальные логи** - вывести все ключи в hex для сравнения

---

## Критическая проблема: Двойная обработка требует немедленного исправления

**Текущее поведение**:
- ChatsViewModel подписывается на все WebSocket сообщения
- ChatViewModel ТОЖЕ подписывается на все WebSocket сообщения
- Оба получают .publicKeyBundle
- Оба пытаются обработать

**Должно быть**:
- ChatViewModel обрабатывает .publicKeyBundle ТОЛЬКО если он initiator
- ChatsViewModel обрабатывает .publicKeyBundle ТОЛЬКО если есть pending first message
- Взаимоисключающая логика!

**Решение**:
```swift
// ChatViewModel.swift
case .publicKeyBundle(let data):
    if data.userId == chat.otherUser?.id {
        guard let currentUserId = SessionManager.shared.currentUserId else { return }
        let isInitiator = currentUserId < data.userId

        if isInitiator {
            // ✅ Только initiator обрабатывает здесь
            // ...
        } else {
            // ❌ Responder НЕ обрабатывает здесь!
            // Это будет обработано в ChatsViewModel
            Log.debug("Ignoring publicKeyBundle as responder - will be handled by ChatsViewModel")
            return
        }
    }
```

---

**Статус**: 🔴 Требуется срочное исправление двойной обработки!
