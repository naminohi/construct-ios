# Ответственность ключей в Construct Messenger

## Обзор

В нашем протоколе используются **5 типов ключей** с чёткой ответственностью.
Критически важно не путать их назначение.

---

## 1. Identity Key (IK) - Долгосрочный ключ идентичности

### Тип
- **Алгоритм**: X25519 (ECDH)
- **Lifetime**: Весь период использования аккаунта (месяцы/годы)
- **Хранение**: На устройстве пользователя (encrypted at rest)

### Назначение
- Криптографическая идентичность пользователя
- Используется в **X3DH DH1**: `DH(IK_Alice, SPK_Bob)`
- **НИКОГДА** не используется напрямую для шифрования сообщений

### Пара ключей
```rust
struct IdentityKeys {
    private: X25519PrivateKey,  // НИКОГДА не покидает устройство
    public: X25519PublicKey,     // Отправляется на сервер при регистрации
}
```

### Когда генерируется
- При первой регистрации пользователя
- При восстановлении аккаунта с нуля

### Ответственность модуля
- `Client::new()` - генерация
- `Client::identity_key` - хранение
- `KeyAgreement::perform_as_initiator()` - использование в X3DH

---

## 2. Signed Prekey (SPK) - Подписанный предварительный ключ

### Тип
- **Алгоритм**: X25519 (ECDH)
- **Lifetime**: Средний срок (дни/недели), ротируется регулярно
- **Подпись**: Ed25519 signature от Signing Key

### Назначение
- Полудолгосрочный ключ для асинхронного key exchange
- Используется в **X3DH DH1 и DH3**:
  - `DH1 = DH(IK_Alice, SPK_Bob)`
  - `DH3 = DH(EK_Alice, SPK_Bob)`
- Позволяет Bob получать сообщения когда он offline

### Пара ключей
```rust
struct SignedPrekeyBundle {
    prekey: X25519PrivateKey,        // На устройстве Bob
    prekey_public: X25519PublicKey,  // На сервере
    signature: Ed25519Signature,     // Подпись prekey_public от signing_key
    prekey_id: u32,                  // ID для ротации
}
```

### Когда генерируется
- При регистрации
- При ротации (рекомендуется каждые 7-30 дней)

### Ответственность модуля
- `Client::new()` - генерация
- `Client::signed_prekey` - хранение
- `Client::rotate_signed_prekey()` - ротация
- `KeyAgreement::perform_as_responder()` - использование в X3DH

### ⚠️ ВАЖНО
Bob должен **сохранять старые signed prekeys** некоторое время после ротации,
потому что Alice может инициировать сессию с устаревшим bundle.

---

## 3. Signing Key - Ключ для подписей

### Тип
- **Алгоритм**: Ed25519 (Signature)
- **Lifetime**: Весь период использования аккаунта
- **Пара**: signing_key (private) + verifying_key (public)

### Назначение
- Подписывать Signed Prekey
- Доказывать, что SPK принадлежит владельцу Identity Key
- **НЕ используется** в DH operations

### Пара ключей
```rust
struct SigningKeys {
    signing_key: Ed25519PrivateKey,      // На устройстве, НИКОГДА не покидает
    verifying_key: Ed25519PublicKey,     // На сервере
}
```

### Когда генерируется
- При регистрации (вместе с Identity Key)

### Использование
```rust
// При регистрации или ротации SPK
let signature = Ed25519::sign(signing_key, signed_prekey_public.as_bytes());

// Alice проверяет перед X3DH
Ed25519::verify(verifying_key, signed_prekey_public.as_bytes(), signature)?;
```

### Ответственность модуля
- `Client::new()` - генерация
- `Client::signing_key` - хранение
- `Client::export_registration_bundle()` - создание подписи SPK
- `KeyAgreement::perform_as_initiator()` - проверка подписи SPK

---

## 4. Ephemeral Key (EK) - Одноразовый эфемерный ключ

### Тип
- **Алгоритм**: X25519 (ECDH)
- **Lifetime**: ОДНА сессия (генерируется заново для каждого контакта)
- **Хранение**: В памяти, уничтожается после использования

### Назначение
- **Forward Secrecy**: компрометация долгосрочных ключей не раскрывает старые сообщения
- Используется в **X3DH DH2 и DH3**:
  - `DH2 = DH(EK_Alice, IK_Bob)`
  - `DH3 = DH(EK_Alice, SPK_Bob)`
- Становится **первым DH Ratchet Key** в Double Ratchet

### Ключевое свойство
```
Alice генерирует EK → использует в X3DH → передаёт EK_public в первом сообщении
→ EK становится первым DH ratchet key → уничтожается после первого ratchet step
```

### Пара ключей
```rust
struct EphemeralKey {
    private: X25519PrivateKey,  // Временно в памяти Alice
    public: X25519PublicKey,    // В первом сообщении Alice → Bob
}
```

### Когда генерируется
- **Alice**: при вызове `Client::initiate_session(bob_id, bob_bundle)`
- **Bob**: НИКОГДА (Bob извлекает EK_public из первого сообщения Alice)

### Ответственность модуля
- `Client::initiate_session()` - генерация
- `KeyAgreement::perform_as_initiator()` - использование в X3DH
- `SecureMessaging::new_initiator_session()` - использование как первый DH ratchet key
- `KeyAgreement::perform_as_responder()` - извлечение из первого сообщения Bob'ом

### ⚠️ КРИТИЧЕСКИ ВАЖНО
**Ephemeral Key НЕ генерируется заново внутри Double Ratchet!**

Было (НЕПРАВИЛЬНО):
```rust
// ❌ BAD: Генерируем новый ключ в Double Ratchet
let (dh_private, dh_public) = P::generate_kem_keys()?;
```

Стало (ПРАВИЛЬНО):
```rust
// ✅ GOOD: Используем X3DH ephemeral key
pub fn new_initiator_session(
    root_key: &[u8],
    initiator_state: InitiatorState<P>,  // Содержит ephemeral_private
    remote_identity: &P::KemPublicKey,
    contact_id: String,
) -> Result<Self, String>
```

---

## 5. DH Ratchet Keys - Ключи Double Ratchet

### Тип
- **Алгоритм**: X25519 (ECDH)
- **Lifetime**: Одно сообщение или пара сообщений (постоянная ротация)
- **Хранение**: В сессии, уничтожаются после ratchet step

### Назначение
- Обеспечивать **forward secrecy** и **backward secrecy** (break-in recovery)
- Каждый ratchet step генерирует новую пару DH ключей

### Ratchet flow
```
Alice отправляет первое сообщение:
  DH_Alice_1 = X3DH Ephemeral Key  ← ВАЖНО: не генерируется заново!
  → encrypt(plaintext_1)
  → EncryptedMessage { dh_public: DH_Alice_1_public, ... }

Bob получает и делает DH ratchet:
  DH_Bob_1 = generate_new_dh_pair()
  root_key_2 = KDF_RK(root_key_1, DH(DH_Bob_1_private, DH_Alice_1_public))
  → encrypt(response)
  → EncryptedMessage { dh_public: DH_Bob_1_public, ... }

Alice получает и делает DH ratchet:
  DH_Alice_2 = generate_new_dh_pair()
  root_key_3 = KDF_RK(root_key_2, DH(DH_Alice_2_private, DH_Bob_1_public))
  ...
```

### Ответственность модуля
- `SecureMessaging::encrypt()` - генерация новых ключей при ratchet step
- `SecureMessaging::decrypt()` - использование remote DH public key для ratchet

---

## Сводная таблица ключей

| Ключ | Алгоритм | Lifetime | X3DH DH1 | X3DH DH2 | X3DH DH3 | Double Ratchet | Подпись SPK |
|------|----------|----------|----------|----------|----------|----------------|-------------|
| **Identity Key (IK)** | X25519 | Годы | ✅ Alice IK | ✅ Bob IK | ❌ | ❌ | ❌ |
| **Signed Prekey (SPK)** | X25519 | Недели | ✅ Bob SPK | ❌ | ✅ Bob SPK | ❌ | ✅ Подписывается |
| **Signing Key** | Ed25519 | Годы | ❌ | ❌ | ❌ | ❌ | ✅ Подписывает |
| **Ephemeral Key (EK)** | X25519 | 1 сессия | ❌ | ✅ Alice EK | ✅ Alice EK | ✅ Первый DH key | ❌ |
| **DH Ratchet Keys** | X25519 | 1 сообщение | ❌ | ❌ | ❌ | ✅ Все остальные | ❌ |

---

## X3DH Protocol - Детальный breakdown

### Alice (инициатор)
```rust
// 1. Alice генерирует ephemeral key
let (EK_A_priv, EK_A_pub) = generate_kem_keys();

// 2. Alice получает Bob's bundle от сервера
BobBundle {
    IK_B_pub: X25519PublicKey,
    SPK_B_pub: X25519PublicKey,
    SPK_signature: Ed25519Signature,
    verifying_key: Ed25519PublicKey,
}

// 3. Alice проверяет подпись SPK
verify(verifying_key, SPK_B_pub.bytes(), SPK_signature)?;

// 4. Alice выполняет 3 DH операции
DH1 = DH(IK_A_priv, SPK_B_pub)  // Alice IK × Bob SPK
DH2 = DH(EK_A_priv, IK_B_pub)   // Alice EK × Bob IK (forward secrecy!)
DH3 = DH(EK_A_priv, SPK_B_pub)  // Alice EK × Bob SPK (forward secrecy!)

// 5. Alice комбинирует секреты
SK = HKDF(DH1 || DH2 || DH3)  // Shared Secret / Root Key

// 6. Alice создаёт Double Ratchet сессию с EK_A_priv как первый DH key
session = DoubleRatchet::new_initiator(SK, EK_A_priv, IK_B_pub)

// 7. Alice шифрует первое сообщение
encrypted = session.encrypt(plaintext)
// encrypted.dh_public_key = EK_A_pub ← Bob извлечёт это!
```

### Bob (получатель)
```rust
// 1. Bob получает первое сообщение от Alice
EncryptedMessage {
    dh_public_key: EK_A_pub,  // ← Alice's ephemeral public key
    ciphertext: ...,
    nonce: ...,
}

// 2. Bob получает Alice's bundle от сервера
AliceBundle {
    IK_A_pub: X25519PublicKey,
    verifying_key: Ed25519PublicKey,
}

// 3. Bob выполняет те же 3 DH операции (но с его стороны)
DH1 = DH(SPK_B_priv, IK_A_pub)  // Bob SPK × Alice IK (reverse!)
DH2 = DH(IK_B_priv, EK_A_pub)   // Bob IK × Alice EK (reverse!)
DH3 = DH(SPK_B_priv, EK_A_pub)  // Bob SPK × Alice EK (reverse!)

// 4. Bob комбинирует секреты (ТОЖЕ САМОЕ значение!)
SK = HKDF(DH1 || DH2 || DH3)  // Тот же Root Key что у Alice

// 5. Bob создаёт Double Ratchet сессию
session = DoubleRatchet::new_responder(SK, IK_B_priv, encrypted_message)

// 6. Bob расшифровывает
plaintext = session.decrypt(encrypted_message)
```

### Математика DH
Почему Alice и Bob получают одинаковые секреты?
```
DH1_Alice = DH(IK_A_priv, SPK_B_pub) = IK_A_priv × SPK_B_pub × G
DH1_Bob   = DH(SPK_B_priv, IK_A_pub) = SPK_B_priv × IK_A_pub × G
          = SPK_B_priv × (IK_A_priv × G) = IK_A_priv × SPK_B_pub × G  ✅ РАВНЫ

Аналогично для DH2 и DH3.
```

---

## Проверочный список (Checklist) при реализации

### ✅ Identity Key
- [ ] Генерируется ОДИН раз при регистрации
- [ ] Private key НИКОГДА не покидает устройство
- [ ] Public key отправляется на сервер
- [ ] Используется в X3DH DH1 и DH2
- [ ] НЕ используется напрямую в Double Ratchet

### ✅ Signed Prekey
- [ ] Генерируется при регистрации
- [ ] Ротируется каждые 7-30 дней
- [ ] Подписывается Signing Key
- [ ] Старые prekeys сохраняются некоторое время
- [ ] Используется в X3DH DH1 и DH3

### ✅ Signing Key
- [ ] Генерируется вместе с Identity Key
- [ ] Используется ТОЛЬКО для подписи SPK
- [ ] Verifying key отправляется на сервер
- [ ] НЕ используется в DH операциях

### ✅ Ephemeral Key
- [ ] Генерируется НОВЫЙ для каждой сессии
- [ ] Alice генерирует при initiate_session()
- [ ] Bob извлекает из первого сообщения
- [ ] Используется в X3DH DH2 и DH3
- [ ] **Становится первым DH Ratchet Key**
- [ ] НЕ генерируется заново в Double Ratchet

### ✅ DH Ratchet Keys
- [ ] Первый DH key = X3DH Ephemeral Key (Alice)
- [ ] Каждый ratchet step генерирует новую пару
- [ ] Старые ключи уничтожаются после использования
- [ ] Public key включается в каждое сообщение

---

## Типичные ошибки (НЕ ДЕЛАТЬ!)

### ❌ Ошибка 1: Генерация нового ключа вместо ephemeral
```rust
// НЕПРАВИЛЬНО
fn new_initiator_session(root_key: &[u8], ...) {
    let (dh_private, _) = P::generate_kem_keys()?;  // ❌ Теряем ephemeral key!
    ...
}

// ПРАВИЛЬНО
fn new_initiator_session(
    root_key: &[u8],
    initiator_state: InitiatorState<P>,  // ✅ Содержит ephemeral key
    ...
) {
    let dh_private = initiator_state.ephemeral_private;
    ...
}
```

### ❌ Ошибка 2: Генерация нового verifying key
```rust
// НЕПРАВИЛЬНО
fn export_registration_bundle(&self) -> Bundle {
    let (_, verifying_key) = P::generate_signature_keys()?;  // ❌ Новый ключ!
    ...
}

// ПРАВИЛЬНО
fn export_registration_bundle(&self) -> Bundle {
    let verifying_key = P::from_signature_private_to_public(&self.signing_key)?;  // ✅
    ...
}
```

### ❌ Ошибка 3: Использование Identity Key для шифрования
```rust
// НЕПРАВИЛЬНО
fn encrypt(plaintext: &[u8]) -> ... {
    let key = self.identity_key;  // ❌ Долгосрочный ключ!
    aead_encrypt(key, plaintext)
}

// ПРАВИЛЬНО - используем chain keys из Double Ratchet
fn encrypt(plaintext: &[u8]) -> ... {
    let (chain_key, msg_key) = KDF_CK(self.sending_chain_key);
    aead_encrypt(msg_key, plaintext)
}
```

---

## Резюме

**Главное правило**: Каждый ключ имеет ОДНУ чёткую ответственность.

1. **Identity Key**: Долгосрочная идентичность, X3DH DH1+DH2
2. **Signed Prekey**: Асинхронный key exchange, X3DH DH1+DH3, ротируется
3. **Signing Key**: Подпись SPK, доказательство владения
4. **Ephemeral Key**: Forward secrecy, X3DH DH2+DH3, первый DH ratchet key
5. **DH Ratchet Keys**: Постоянная ротация в Double Ratchet

**Критические точки**:
- Ephemeral Key используется дважды: сначала в X3DH, потом как первый DH ratchet key
- Bob НИКОГДА не генерирует ephemeral key - он извлекает его из первого сообщения
- Signing Key используется ТОЛЬКО для подписи, НИКОГДА для DH
