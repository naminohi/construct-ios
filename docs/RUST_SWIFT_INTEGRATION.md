# 🔗 Rust + Swift Integration Guide (UniFFI)

**Статус:** ✅ Production Ready
**Дата:** 26 декабря 2025
**Технология:** UniFFI 0.28 от Mozilla

---

## 📋 Оглавление

1. [Обзор архитектуры](#обзор-архитектуры)
2. [Структура проекта](#структура-проекта)
3. [Настройка Rust](#настройка-rust)
4. [Настройка Xcode](#настройка-xcode)
5. [Чистый API дизайн](#чистый-api-дизайн)
6. [Сборка и интеграция](#сборка-и-интеграция)
7. [Безопасность](#безопасность)
8. [Отладка](#отладка)

---

## 🏗️ Обзор архитектуры

### Принцип "Тонкая обертка"

```
┌─────────────────────────────────────────┐
│           Swift Layer (UI)              │
│  ❌ НЕТ криптографии                    │
│  ❌ НЕТ MessagePack                     │
│  ✅ Только UI и передача данных         │
└──────────────┬──────────────────────────┘
               │ UniFFI
┌──────────────▼──────────────────────────┐
│          Rust Core (Logic)              │
│  ✅ ВСЯ криптография                    │
│  ✅ Double Ratchet Protocol             │
│  ✅ MessagePack сериализация            │
│  ✅ Session management                  │
└─────────────────────────────────────────┘
```

**Философия:** Swift = черный ящик, Rust = силовая установка (90% логики)

---

## 📁 Структура проекта

```
construct-messenger/
├── packages/core/              # Rust криптографическое ядро
│   ├── src/
│   │   ├── lib.rs             # Экспорт UniFFI типов
│   │   ├── uniffi_bindings.rs # UniFFI wrapper layer
│   │   ├── construct_core.udl # UniFFI интерфейс (IDL)
│   │   ├── crypto/            # Криптографические модули
│   │   │   ├── classic_suite.rs    # X25519 + Ed25519 + ChaCha20
│   │   │   ├── crypto_provider.rs  # Trait для crypto-agility
│   │   │   ├── double_ratchet.rs   # Double Ratchet Protocol
│   │   │   └── x3dh.rs             # Extended Triple DH
│   │   └── api/
│   │       └── crypto.rs      # High-level Crypto API
│   ├── Cargo.toml
│   └── build.rs               # UniFFI build script
│
├── ConstructMessenger/         # iOS Swift приложение
│   ├── Security/
│   │   └── CryptoManager.swift        # Тонкая обертка над Rust
│   ├── construct_core.swift           # UniFFI сгенерированный код
│   ├── construct_coreFFI.h            # C заголовки для FFI
│   └── ConstructMessenger-Bridging-Header.h
│
└── libconstruct_core.a        # Скомпилированная Rust библиотека
```

---

## ⚙️ Настройка Rust

### 1. Cargo.toml

```toml
[package]
name = "construct-core"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["staticlib", "cdylib", "rlib"]

[dependencies]
uniffi = { version = "0.28", features = ["build"] }
x25519-dalek = "2.0"
ed25519-dalek = "2.0"
chacha20poly1305 = "0.10"
hkdf = "0.12"
sha2 = "0.10"
rand = "0.8"
base64 = "0.22"
rmp-serde = "1.1"  # MessagePack
serde = { version = "1.0", features = ["derive"] }
thiserror = "1.0"

[build-dependencies]
uniffi = { version = "0.28", features = ["build"] }
```

### 2. build.rs

```rust
fn main() {
    uniffi::generate_scaffolding("src/construct_core.udl")
        .expect("Failed to generate UniFFI scaffolding");
}
```

### 3. construct_core.udl (интерфейс)

```idl
namespace construct_core {};

// Структура для зашифрованного сообщения (wire format)
dictionary EncryptedMessageComponents {
    sequence<u8> ephemeral_public_key;  // 32 байта
    u32 message_number;
    string content;  // Base64(nonce || ciphertext_with_tag)
};

// Ошибки
[Error]
enum CryptoError {
    "InitializationFailed",
    "SessionNotFound",
    "EncryptionFailed",
    "DecryptionFailed",
    "InvalidKeyData",
};

// Основной класс
interface ClassicCryptoCore {
    [Throws=CryptoError]
    string export_registration_bundle_json();

    [Throws=CryptoError]
    string init_session(string contact_id, sequence<u8> recipient_bundle);

    [Throws=CryptoError]
    EncryptedMessageComponents encrypt_message(string session_id, string plaintext);

    [Throws=CryptoError]
    string decrypt_message(
        string session_id,
        sequence<u8> ephemeral_public_key,
        u32 message_number,
        string content
    );
};

namespace construct_core {
    [Throws=CryptoError]
    ClassicCryptoCore create_crypto_core();
};
```

### 4. uniffi_bindings.rs (реализация)

```rust
use crate::api::crypto::CryptoCore;
use crate::crypto::classic_suite::ClassicSuiteProvider;
use base64::Engine as _;
use std::sync::{Arc, Mutex};

pub struct ClassicCryptoCore {
    inner: Mutex<CryptoCore<ClassicSuiteProvider>>,
}

#[derive(Debug, Clone)]
pub struct EncryptedMessageComponents {
    pub ephemeral_public_key: Vec<u8>,
    pub message_number: u32,
    pub content: String,
}

impl ClassicCryptoCore {
    pub fn encrypt_message(
        &self,
        session_id: String,
        plaintext: String,
    ) -> Result<EncryptedMessageComponents, CryptoError> {
        let mut core = self.inner.lock().unwrap();
        let encrypted_message = core
            .encrypt_message(&session_id, &plaintext)
            .map_err(|_| CryptoError::EncryptionFailed)?;

        // Создаем sealed box: nonce || ciphertext_with_tag
        let mut sealed_box = Vec::new();
        sealed_box.extend_from_slice(&encrypted_message.nonce);
        sealed_box.extend_from_slice(&encrypted_message.ciphertext);

        Ok(EncryptedMessageComponents {
            ephemeral_public_key: encrypted_message.dh_public_key.to_vec(),
            message_number: encrypted_message.message_number,
            content: base64::engine::general_purpose::STANDARD.encode(&sealed_box),
        })
    }

    pub fn decrypt_message(
        &self,
        session_id: String,
        ephemeral_public_key: Vec<u8>,
        message_number: u32,
        content: String,
    ) -> Result<String, CryptoError> {
        // Decode base64 sealed box
        let sealed_box = base64::engine::general_purpose::STANDARD
            .decode(&content)
            .map_err(|_| CryptoError::InvalidCiphertext)?;

        // Extract nonce and ciphertext
        if sealed_box.len() < 12 {
            return Err(CryptoError::InvalidCiphertext);
        }
        let nonce = sealed_box[..12].to_vec();
        let ciphertext = sealed_box[12..].to_vec();

        // Convert to [u8; 32]
        let dh_public_key: [u8; 32] = ephemeral_public_key
            .try_into()
            .map_err(|_| CryptoError::InvalidKeyData)?;

        // Reconstruct message
        let encrypted_message = crate::crypto::double_ratchet::EncryptedRatchetMessage {
            dh_public_key,
            message_number,
            ciphertext,
            nonce,
            previous_chain_length: 0,
            suite_id: 1,
        };

        let mut core = self.inner.lock().unwrap();
        core.decrypt_message(&session_id, &encrypted_message)
            .map_err(|_| CryptoError::DecryptionFailed)
    }
}

pub fn create_crypto_core() -> Result<Arc<ClassicCryptoCore>, CryptoError> {
    let core = CryptoCore::<ClassicSuiteProvider>::new()
        .map_err(|_| CryptoError::InitializationFailed)?;

    Ok(Arc::new(ClassicCryptoCore {
        inner: Mutex::new(core),
    }))
}
```

### 5. lib.rs (экспорт)

```rust
#[cfg(not(target_arch = "wasm32"))]
pub mod uniffi_bindings;

#[cfg(not(target_arch = "wasm32"))]
pub use uniffi_bindings::{
    ClassicCryptoCore,
    CryptoError,
    EncryptedMessageComponents,
    create_crypto_core
};

#[cfg(not(target_arch = "wasm32"))]
uniffi::include_scaffolding!("construct_core");
```

---

## 📱 Настройка Xcode

### 1. Сборка библиотеки

```bash
# В папке packages/core
cargo build --release --target aarch64-apple-ios

# Генерация Swift bindings
uniffi-bindgen generate \
  --library ../../target/aarch64-apple-ios/release/libconstruct_core.a \
  --language swift \
  --out-dir bindings/swift

# Копирование в Xcode проект
cp ../../target/aarch64-apple-ios/release/libconstruct_core.a ../../libconstruct_core.a
cp bindings/swift/construct_core.swift ../../ConstructMessenger/
cp bindings/swift/construct_coreFFI.h ../../ConstructMessenger/
```

### 2. Bridging Header

**ConstructMessenger-Bridging-Header.h:**
```objc
#ifndef ConstructMessenger_Bridging_Header_h
#define ConstructMessenger_Bridging_Header_h

// UniFFI generated C header
#import "construct_coreFFI.h"

#endif
```

### 3. Xcode Build Settings

- **Library Search Paths:** `$(PROJECT_DIR)/..`
- **Other Linker Flags:** `-lconstruct_core`
- **Objective-C Bridging Header:** `$(PROJECT_DIR)/ConstructMessenger/ConstructMessenger-Bridging-Header.h`

### 4. Добавить файлы в проект

1. `libconstruct_core.a` → Link Binary With Libraries
2. `construct_core.swift` → Compile Sources
3. `construct_coreFFI.h` → Copy Bundle Resources (или Headers)

---

## 🎯 Чистый API дизайн

### Swift тонкая обертка

**CryptoManager.swift:**
```swift
import Foundation

class CryptoManager {
    static let shared = CryptoManager()

    private var core: ClassicCryptoCore?
    private var userSessions: [String: String] = [:]

    private init() {
        do {
            self.core = try createCryptoCore()
        } catch {
            fatalError("Failed to create CryptoCore: \(error)")
        }
    }

    // ШИФРОВАНИЕ: Swift передает plaintext, получает wire format
    func encryptMessage(_ message: String, for userId: String) throws -> EncryptedMessageComponents {
        guard let core = core else {
            throw CryptoManagerError.coreNotInitialized
        }
        guard let sessionId = userSessions[userId] else {
            throw CryptoManagerError.sessionNotFound
        }

        // ✅ Rust делает ВСЁ: MessagePack, Double Ratchet, шифрование
        let rustComponents = try core.encryptMessage(
            sessionId: sessionId,
            plaintext: message
        )

        // Просто конвертируем в Swift struct
        return EncryptedMessageComponents(
            ephemeralPublicKey: Data(rustComponents.ephemeralPublicKey),
            messageNumber: rustComponents.messageNumber,
            content: rustComponents.content
        )
    }

    // РАСШИФРОВКА: Swift передает wire format, получает plaintext
    func decryptMessage(_ message: ChatMessage) throws -> String {
        guard let core = core else {
            throw CryptoManagerError.coreNotInitialized
        }
        guard let sessionId = userSessions[message.from] else {
            throw CryptoManagerError.sessionNotFound
        }

        // ✅ Rust делает ВСЁ: парсинг, Double Ratchet, расшифровку
        return try core.decryptMessage(
            sessionId: sessionId,
            ephemeralPublicKey: [UInt8](message.ephemeralPublicKey),
            messageNumber: message.messageNumber,
            content: message.content
        )
    }
}
```

**Ключевые принципы:**
- ❌ Swift НЕ знает о MessagePack
- ❌ Swift НЕ знает о Double Ratchet
- ✅ Swift только передает wire format (ephemeralKey, msgNum, content)
- ✅ Rust обрабатывает ВСЁ криптографическое

---

## 🔐 Безопасность

### Memory Safety

1. **Удалены все `unsafe` блоки** из Rust кода
2. **UniFFI автоматически управляет памятью** через `Arc<T>`
3. **Нет ручного `Drop`** - Rust ownership rules работают автоматически

### Crypto-Agility

```rust
pub trait CryptoProvider {
    type KemPublicKey;
    type KemPrivateKey;
    type SignaturePublicKey;
    type SignaturePrivateKey;
    type AeadKey;

    fn generate_kem_keys() -> Result<(Self::KemPrivateKey, Self::KemPublicKey)>;
    fn aead_encrypt(...) -> Result<Vec<u8>>;
    fn aead_decrypt(...) -> Result<Vec<u8>>;
    // ...
}

// Classic suite (X25519 + Ed25519 + ChaCha20)
pub struct ClassicSuiteProvider;
impl CryptoProvider for ClassicSuiteProvider { ... }

// Post-Quantum suite (future)
pub struct PQSuiteProvider;
impl CryptoProvider for PQSuiteProvider { ... }
```

---

## 🔧 Сборка и интеграция

### Автоматизация сборки

**build.sh:**
```bash
#!/bin/bash
set -e

cd packages/core

# Build for iOS
cargo build --release --target aarch64-apple-ios

# Generate Swift bindings
uniffi-bindgen generate \
  --library ../../target/aarch64-apple-ios/release/libconstruct_core.a \
  --language swift \
  --out-dir bindings/swift

# Copy to Xcode project
cp ../../target/aarch64-apple-ios/release/libconstruct_core.a ../../libconstruct_core.a
cp bindings/swift/construct_core.swift ../../ConstructMessenger/construct_core.swift
cp bindings/swift/construct_coreFFI.h ../../ConstructMessenger/construct_coreFFI.h

echo "✅ Build complete! Open Xcode and build the project."
```

### В Xcode

1. **Clean Build Folder** (⇧⌘K)
2. **Build** (⌘B)
3. **Run** (⌘R)

---

## 🐛 Отладка

### Логирование в Rust

```rust
// В Rust используй eprintln! для stderr
eprintln!("[Rust] Decrypting message: msgNum={}", message_number);
```

**⚠️ Важно:** На iOS `eprintln!` **НЕ** выводится в Xcode console по умолчанию. Используйте:
- `println!` для stdout (работает в Xcode)
- Или возвращайте детальные ошибки через `CryptoError`

### Проверка типов

```bash
# Показать экспортированные символы
nm -gU libconstruct_core.a | grep uniffi
```

### Частые проблемы

| Проблема | Решение |
|----------|---------|
| `ClassicCryptoCore is ambiguous` | Удалить старые bindings файлы, почистить DerivedData |
| `Library not found` | Проверить Library Search Paths в Build Settings |
| Двойное освобождение памяти | Убрать ручные `Drop` implementations, доверять UniFFI |
| Логи не появляются | Использовать `println!` вместо `eprintln!` на iOS |

---

## 📚 Дополнительные ресурсы

- [UniFFI Documentation](https://mozilla.github.io/uniffi-rs/)
- [API_V3_SPEC.md](./API_V3_SPEC.md) - Полная спецификация API
- [ROADMAP.md](./ROADMAP.md) - План развития crypto-agility

---

**Статус:** ✅ Production Ready
**Последнее обновление:** 26 декабря 2025
