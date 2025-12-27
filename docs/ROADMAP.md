# 🗺️ Construct Messenger Roadmap

**Дата:** 26 декабря 2025
**Текущая версия:** v0.1.0 (iOS UniFFI + Rust Core)
**Цель:** Построение крипто-гибкого мессенджера с поддержкой постквантовых алгоритмов

---

## 📊 Текущий статус (Декабрь 2025)

### ✅ Завершено

#### Crypto Core (Rust)
- ✅ Double Ratchet Protocol (Signal Protocol)
- ✅ X3DH key agreement
- ✅ Classic crypto suite:
  - X25519 (ECDH)
  - Ed25519 (подписи)
  - ChaCha20-Poly1305 (AEAD)
- ✅ Crypto-agility через `CryptoProvider` trait
- ✅ 100% безопасный код (0 `unsafe` блоков)
- ✅ MessagePack сериализация
- ✅ Session management

#### iOS Integration
- ✅ UniFFI bindings (миграция с swift-bridge)
- ✅ Чистый API дизайн (тонкая Swift обертка)
- ✅ Xcode интеграция
- ✅ Core Data persistence
- ✅ WebSocket клиент

#### Server
- ✅ Rust WebSocket сервер (Actix)
- ✅ MessagePack протокол
- ✅ PostgreSQL с миграциями
- ✅ User authentication (session tokens)
- ✅ Message routing
- ✅ Key bundle storage

### 🚧 Текущие проблемы

- ⚠️ Расшифровка сообщений падает (отладка в процессе)
- ⚠️ Двойная обработка входящих сообщений (исправлено)
- ⚠️ Нужна оптимизация session state sync

---

## 🎯 Фаза 1: Стабилизация (Январь 2026)

**Цель:** Полнофункциональный iOS мессенджер с классической криптографией

### Приоритет 1: Исправление критических багов
- [ ] Исправить расшифровку сообщений
- [ ] Протестировать Double Ratchet с множественными сессиями
- [ ] Добавить обработку out-of-order messages
- [ ] Реализовать message retry logic

### Приоритет 2: Улучшение UX
- [ ] Push notifications (APNs)
- [ ] Typing indicators
- [ ] Read receipts
- [ ] Message editing/deletion
- [ ] File attachments (изображения)

### Приоритет 3: Тестирование
- [ ] Unit тесты для crypto core (Rust)
- [ ] Integration тесты для protocol
- [ ] UI тесты (Swift)
- [ ] Load testing (сервер)
- [ ] Security audit

### Приоритет 4: Документация
- [x] Rust+Swift integration guide
- [x] Roadmap
- [ ] API documentation (Rust docs)
- [ ] User manual
- [ ] Deployment guide

**Результат:** Готовый к бета-тестированию мессенджер

---

## 🔐 Фаза 2: Post-Quantum Cryptography (Q2 2026)

**Цель:** Гибридные постквантовые схемы для защиты от квантовых компьютеров

### 2.1 Исследование и выбор алгоритмов

#### Key Encapsulation (KEM)
- [ ] **Kyber** (NIST стандарт ML-KEM)
  - Kyber-512 (Level 1)
  - Kyber-768 (Level 3) ← **рекомендуется**
  - Kyber-1024 (Level 5)
- [ ] Альтернативы: NTRU, SIKE, HQC

#### Digital Signatures
- [ ] **Dilithium** (NIST стандарт ML-DSA)
  - Dilithium2 (Level 2)
  - Dilithium3 (Level 3) ← **рекомендуется**
  - Dilithium5 (Level 5)
- [ ] Альтернативы: Falcon, SPHINCS+

### 2.2 Гибридные схемы

**Принцип:** Комбинировать классические и PQ алгоритмы для backward compatibility

```
Hybrid KEM = X25519 ⊕ Kyber768
Hybrid Signature = Ed25519 + Dilithium3
```

**Причина:**
- ✅ Защита от квантовых атак (PQ алгоритмы)
- ✅ Защита от уязвимостей в новых алгоритмах (классические алгоритмы)
- ✅ Совместимость с устаревшими клиентами

### 2.3 Реализация

#### Rust Core
```rust
// Новый crypto provider
pub struct PQSuiteProvider;

impl CryptoProvider for PQSuiteProvider {
    type KemPublicKey = HybridKemPublicKey;  // X25519 + Kyber768
    type SignaturePublicKey = HybridSigPublicKey;  // Ed25519 + Dilithium3

    fn generate_kem_keys() -> Result<(Self::KemPrivateKey, Self::KemPublicKey)> {
        // 1. Generate X25519 keys
        let (x25519_sk, x25519_pk) = x25519_generate();

        // 2. Generate Kyber768 keys
        let (kyber_sk, kyber_pk) = kyber768_generate();

        // 3. Combine
        Ok((
            HybridKemPrivateKey { x25519_sk, kyber_sk },
            HybridKemPublicKey { x25519_pk, kyber_pk }
        ))
    }

    fn kem_encapsulate(pk: &Self::KemPublicKey) -> Result<(Vec<u8>, Vec<u8>)> {
        // 1. X25519 encapsulation
        let (x25519_ct, x25519_ss) = x25519_encaps(&pk.x25519_pk)?;

        // 2. Kyber768 encapsulation
        let (kyber_ct, kyber_ss) = kyber768_encaps(&pk.kyber_pk)?;

        // 3. Combine ciphertexts and shared secrets
        let ct = concat(x25519_ct, kyber_ct);
        let ss = xor(x25519_ss, kyber_ss);  // или KDF(x25519_ss || kyber_ss)

        Ok((ct, ss))
    }

    // ...
}
```

#### Wire Format
```json
{
  "suite_id": 2,  // PQ Hybrid Suite
  "identity_public": "base64(x25519_pk || kyber_pk)",
  "signed_prekey_public": "base64(x25519_pk || kyber_pk)",
  "signature": "base64(ed25519_sig || dilithium_sig)",
  "verifying_key": "base64(ed25519_vk || dilithium_vk)"
}
```

### 2.4 Задачи

- [ ] Добавить `pqcrypto-kyber` dependency
- [ ] Добавить `pqcrypto-dilithium` dependency
- [ ] Реализовать `PQSuiteProvider`
- [ ] Обновить `suite_id` negotiation в протоколе
- [ ] Тестирование совместимости с классическими клиентами
- [ ] Benchmark размеров ключей и производительности

### 2.5 Метрики

| Алгоритм | Public Key | Secret Key | Ciphertext | Signature |
|----------|-----------|-----------|------------|-----------|
| **Classic** (X25519 + Ed25519) | 64 B | 64 B | 32 B | 64 B |
| **PQ Hybrid** (Kyber768 + Dilithium3) | 1856 B | 2720 B | 1152 B | 3366 B |
| **Увеличение** | 29x | 42x | 36x | 52x |

**Вывод:** Значительное увеличение размера → нужна оптимизация bandwidth

**Результат:** Production-ready постквантовое шифрование

---

## 🌐 Фаза 3: Multi-Platform (Q3-Q4 2026)

**Цель:** Поддержка всех платформ с единым Rust ядром

### 3.1 Android
- [ ] UniFFI bindings для Kotlin/Android
- [ ] Jetpack Compose UI
- [ ] Android KeyStore integration
- [ ] Google Play release

### 3.2 Web (WASM)
- [ ] Восстановить WASM bindings (wasm-bindgen)
- [ ] React/TypeScript PWA
- [ ] IndexedDB для persistence
- [ ] Web Crypto API integration

### 3.3 Desktop
- [ ] macOS (SwiftUI + UniFFI)
- [ ] Windows (C# + UniFFI или Tauri)
- [ ] Linux (GTK/Qt + Rust FFI)

### 3.4 Единое ядро

```
                    ┌─────────────────┐
                    │   Rust Core     │
                    │  (90% логики)   │
                    └────────┬────────┘
                             │
        ┌────────────────────┼────────────────────┐
        │                    │                    │
   ┌────▼────┐          ┌────▼────┐         ┌────▼────┐
   │  iOS    │          │ Android │         │  WASM   │
   │ UniFFI  │          │ UniFFI  │         │wasm-bind│
   └─────────┘          └─────────┘         └─────────┘
```

**Результат:** Write once (Rust), run everywhere

---

## 🚀 Фаза 4: Advanced Features (2027)

### 4.1 Group Messaging
- [ ] Sender Keys (Signal Groups Protocol)
- [ ] Member management
- [ ] Group invites
- [ ] Admin permissions

### 4.2 Voice/Video Calls
- [ ] WebRTC integration
- [ ] SRTP encryption
- [ ] P2P hole punching
- [ ] TURN/STUN servers

### 4.3 Backup & Sync
- [ ] Encrypted cloud backup
- [ ] Multi-device sync
- [ ] Message history export

### 4.4 Advanced Security
- [ ] Sealed sender (metadata hiding)
- [ ] Disappearing messages
- [ ] Screenshot prevention
- [ ] Secure Enclave usage (iOS)

---

## 🌐 Фаза 5: Федерация серверов (2028+)

**Цель:** Децентрализованная архитектура по модели email/XMPP - пользователи разных серверов могут общаться между собой

### Концепция: "Email 2.0" с E2E шифрованием

```
alice@server1.com ←──[E2E encrypted]──→ bob@server2.com
                   └─────[Federation]─────┘
```

**Философия:**
- Нет центрального сервера (как email)
- Каждый может развернуть свой сервер
- E2E шифрование защищает от compromised серверов
- DNS-based server discovery

---

### 5.1 Federated User Identity

**Переход от UUID к federated ID:**

```rust
// CURRENT (Centralized)
UserId = "550e8400-e29b-41d4-a716-446655440000"

// FUTURE (Federated)
FederatedId = "alice@construct.example.com"
              └─┬─┘ └──────┬─────────────┘
            username     homeserver
```

**Задачи:**
- [ ] Добавить поддержку `username@domain` формата
- [ ] Backward compatibility с UUID (migration path)
- [ ] Валидация доменных имен
- [ ] Reserved usernames (@admin, @system, etc.)

---

### 5.2 DNS-Based Server Discovery

**Принцип работы (как XMPP/Matrix):**

```bash
# 1. Клиент хочет отправить сообщение bob@another-server.com
# 2. DNS lookup для SRV record:
dig _construct._tcp.another-server.com SRV

# 3. Ответ:
_construct._tcp.another-server.com. 86400 IN SRV 0 5 8448 federation.another-server.com.

# 4. Установить HTTPS соединение с federation.another-server.com:8448
```

**Задачи:**
- [ ] Реализовать DNS SRV lookup
- [ ] Fallback на HTTPS well-known (`.well-known/construct`)
- [ ] TLS certificate validation
- [ ] Connection pooling для S2S соединений

---

### 5.3 Server-to-Server (S2S) Protocol

**Архитектура:**

```
┌──────────────────┐         ┌──────────────────┐
│   Server 1       │         │   Server 2       │
│                  │         │                  │
│  alice (client)  │         │  bob (client)    │
│       │          │         │       ▲          │
│       ▼          │         │       │          │
│  [Outbound       │ ◄─────► │  [Inbound        │
│   Federation]    │  HTTPS  │   Federation]    │
└──────────────────┘         └──────────────────┘
```

**API Endpoints:**

```rust
// POST https://server2.com/federation/v1/send
{
    "event_id": "7c9e6679-7425-...",
    "origin": "server1.com",
    "destination": "server2.com",
    "created_at": 1735689600,
    "event": {
        "type": "message",
        "from": "alice@server1.com",
        "to": "bob@server2.com",
        "e2e_encrypted": "..."  // Only bob can decrypt
    },
    "signature": "..."  // Server1's signing key
}
```

**Задачи:**
- [ ] S2S HTTPS API specification
- [ ] Server signing keys (Ed25519)
- [ ] Signature verification для защиты от spoofing
- [ ] Event validation и sanitization
- [ ] Rate limiting на S2S уровне

---

### 5.4 Event Graph (Distributed Message History)

**Проблема:** Два сервера могут получить сообщения в разном порядке

**Решение:** DAG (Directed Acyclic Graph) как в Matrix

```
Event A (server1) ──┐
                    ├──> Event C (merge, references A+B)
Event B (server2) ──┘

Each event contains:
- event_id
- prev_events: [parent_event_ids]
- depth: number
- signature: server_signature
```

**Задачи:**
- [ ] Event graph data structure
- [ ] Conflict resolution algorithm
- [ ] State resolution для ordering
- [ ] Merkle tree для integrity verification

---

### 5.5 Trust & Security

#### 5.5.1 Server Signing Keys

```rust
pub struct ServerIdentity {
    domain: String,
    signing_key: Ed25519PublicKey,
    valid_until: Timestamp,
}

// Публикуется через:
GET https://server1.com/.well-known/construct/server-keys
{
    "server_name": "server1.com",
    "verify_keys": {
        "ed25519:2025": "base64_public_key"
    },
    "valid_until_ts": 1735689600,
    "signatures": { ... }
}
```

**Задачи:**
- [ ] Server key generation при первом запуске
- [ ] Key rotation mechanism
- [ ] Key transparency log (CT-подобная система)

#### 5.5.2 Sealed Sender (Metadata Privacy)

**Проблема:** Server2 знает, что alice@server1.com пишет bob

**Решение:** Anonymous message routing

```rust
// Server1 не указывает отправителя при S2S передаче
{
    "from": "ANONYMOUS",  // Hidden from server2
    "to": "bob@server2.com",
    "sealed_envelope": "..."  // Contains real sender, encrypted to bob's key
}

// Только bob может расшифровать и узнать отправителя
```

**Задачи:**
- [ ] Sealed sender encryption layer
- [ ] Reply mechanism без раскрытия sender
- [ ] Abuse prevention (spam filtering без metadata)

#### 5.5.3 Server Reputation System

**Проблема:** Spam и malicious серверы

**Решение:** Reputation scoring

```rust
pub struct ServerReputation {
    domain: String,
    trust_score: f64,  // 0.0 - 1.0
    spam_reports: u64,
    last_verified: Timestamp,
}

// Distributed reputation network
// Серверы обмениваются reputation data
```

**Задачи:**
- [ ] Reputation scoring algorithm
- [ ] Blocklist/allowlist management
- [ ] Proof-of-Work для новых серверов
- [ ] Community-driven moderation

---

### 5.6 Contact Discovery

**Проблема:** Как alice находит bob@another-server.com?

**Решение 1:** DNS-based lookup (public)
```bash
dig _construct-user._tcp.bob.another-server.com TXT
# Returns: public key bundle
```

**Решение 2:** Private Information Retrieval (PIR)
- Клиент запрашивает контакты без раскрытия запроса
- Криптографически защищенный поиск
- Базируется на homomorphic encryption

**Задачи:**
- [ ] DNS TXT records для public key distribution
- [ ] PIR protocol implementation (optional)
- [ ] Contact verification через QR codes

---

### 5.7 Migration Path от Centralized к Federated

**Стратегия обратной совместимости:**

```rust
// Phase 1: Centralized (current)
UserId = UUID

// Phase 2: Soft federation
UserId = UUID OR "username@domain"
Default domain: "construct.app"

// Phase 3: Full federation
UserId = "username@domain" (UUID deprecated)
```

**Задачи:**
- [ ] Dual-mode server (centralized + federated)
- [ ] UUID → federated ID mapping
- [ ] Migration assistant для пользователей
- [ ] Gradual rollout strategy

---

### 5.8 Implementation Roadmap

**Q1 2028:**
- [ ] Spec finalization (S2S API, event format)
- [ ] DNS integration
- [ ] Server signing keys

**Q2 2028:**
- [ ] S2S protocol implementation
- [ ] Basic federation (two servers)
- [ ] Testing infrastructure

**Q3 2028:**
- [ ] Event graph
- [ ] Conflict resolution
- [ ] Multi-server sync

**Q4 2028:**
- [ ] Sealed sender
- [ ] Reputation system
- [ ] Production rollout

---

### 5.9 Сравнение с существующими протоколами

| Протокол | Федерация | E2E | Формат | Сложность |
|----------|-----------|-----|---------|-----------|
| **Email (SMTP)** | ✅ | ❌ | Text | Low |
| **XMPP** | ✅ | ⚠️ (OMEMO) | XML | Medium |
| **Matrix** | ✅ | ✅ (Olm) | JSON | High |
| **Signal** | ❌ | ✅ | Protobuf | Low |
| **Construct (future)** | ✅ | ✅ (Double Ratchet) | MessagePack | Medium |

**Преимущества Construct Federation:**
- ✅ Rust безопасность на всех уровнях
- ✅ MessagePack (легче XML, эффективнее JSON)
- ✅ Уже реализован Double Ratchet
- ✅ Post-quantum ready architecture

---

### 5.10 Метрики успеха (2028)

- ✅ Минимум 3 независимых сервера в федерации
- ✅ < 500ms latency для federated messages
- ✅ 99% successful S2S message delivery
- ✅ 0 metadata leaks (sealed sender работает)
- ✅ Публичная спецификация Federation Protocol
- ✅ Reference implementation (open source)

---

### 5.11 Риски и mitigation

**Риск 1:** Spam и abuse
- **Mitigation:** Reputation system, proof-of-work, rate limiting

**Риск 2:** Server impersonation
- **Mitigation:** TLS certificates, signing keys, key transparency

**Риск 3:** Network partitions
- **Mitigation:** Event graph, eventual consistency, offline support

**Риск 4:** Complexity overhead
- **Mitigation:** Gradual rollout, backward compatibility, clear documentation

---

## 🔬 Исследовательские направления

### Crypto Innovations
- [ ] **Zero-Knowledge Proofs** для анонимной аутентификации
- [ ] **Homomorphic Encryption** для server-side search
- [ ] **MLS (Messaging Layer Security)** для групповых чатов
- [ ] **Noise Protocol Framework** как альтернатива Double Ratchet

### Performance
- [ ] **Parallel ratcheting** для улучшения throughput
- [ ] **Lazy key derivation** для уменьшения latency
- [ ] **Batch operations** для множественных сообщений

### Privacy
- [ ] **Tor integration** для анонимности
- [ ] **Private Information Retrieval** для contact discovery
- [ ] **Anonymous credentials** для регистрации

---

## 📈 Метрики успеха

### Q1 2026
- ✅ 100% core features работают
- ✅ 0 критических багов
- ✅ < 100ms latency для encryption/decryption
- ✅ Security audit passed

### Q2 2026
- ✅ PQ hybrid схемы реализованы
- ✅ Backward compatibility с classic suite
- ✅ < 500ms latency с PQ алгоритмами

### Q3-Q4 2026
- ✅ iOS + Android + Web версии
- ✅ 10,000+ active users (бета)
- ✅ 99.9% uptime

### 2027
- ✅ Voice/video calls
- ✅ Group messaging
- ✅ 100,000+ active users

### 2028+
- ✅ Federation protocol specification
- ✅ Минимум 3 независимых сервера
- ✅ Sealed sender для metadata privacy
- ✅ 1,000,000+ federated users

---

## 🛡️ Безопасность

### Continuous Security
- Регулярные audits кодовой базы
- Penetration testing
- Bug bounty program
- Responsible disclosure policy

### Compliance
- GDPR compliance (Europe)
- CCPA compliance (California)
- E2EE best practices (Signal Protocol)

---

## 📚 Ресурсы

### Документация
- [RUST_SWIFT_INTEGRATION.md](./RUST_SWIFT_INTEGRATION.md) - Интеграция Rust+Swift
- [API_V3_SPEC.md](./API_V3_SPEC.md) - Полная спецификация API
- [security/post-quantum-cryptography.md](./security/post-quantum-cryptography.md) - PQ крипто

### Библиотеки
- **pqcrypto** - Rust PQ криптография
- **signal-protocol** - Reference implementation
- **UniFFI** - Multi-language bindings

### Standards
- [NIST PQC](https://csrc.nist.gov/projects/post-quantum-cryptography) - NIST постквантовая криптография
- [Signal Protocol](https://signal.org/docs/) - Double Ratchet спецификация
- [RFC 9180 HPKE](https://datatracker.ietf.org/doc/rfc9180/) - Hybrid Public Key Encryption
- [Matrix Spec](https://spec.matrix.org/latest/) - Федеративный протокол обмена сообщениями
- [XMPP RFC 6120](https://datatracker.ietf.org/doc/html/rfc6120) - Extensible Messaging and Presence Protocol

---

**Дата последнего обновления:** 26 декабря 2025
**Версия roadmap:** 2.0 (добавлена Фаза 5: Федерация)
**Мейнтейнер:** Maxim Eliseyev
