# Post-Quantum Hybrid Криптография

## Цель
Обеспечить защиту от квантовых компьютеров **БЕЗ потери** безопасности классической криптографии.

## Принцип: Hybrid = Classical + Post-Quantum

**Ключевая идея**: Использовать **оба** алгоритма одновременно.

```
Security = MIN(Classical_Security, PQ_Security)
```

Если квантовый алгоритм окажется сломанным → остаётся classical security.
Если квантовый компьютер появится → есть PQ protection.

## Выбор алгоритмов

### Classical Suite (текущая реализация)
- **KEM (Key Exchange)**: X25519 (ECDH на Curve25519)
- **Signatures**: Ed25519
- **AEAD**: ChaCha20-Poly1305
- **KDF**: HKDF-SHA256

### Post-Quantum Suite (NIST стандарты)
- **KEM**: ML-KEM-768 (Kyber768) - NIST FIPS 203
- **Signatures**: ML-DSA-65 (Dilithium3) - NIST FIPS 204
- **AEAD**: остаётся ChaCha20-Poly1305 (квантово-безопасный)
- **KDF**: остаётся HKDF-SHA256 (квантово-безопасный)

### Почему именно эти алгоритмы?

**ML-KEM-768 (Kyber768)**:
- Стандартизован NIST (FIPS 203)
- Безопасность: эквивалентна AES-192
- Размеры: public key 1184 bytes, ciphertext 1088 bytes
- Производительность: очень быстрый (~10x быстрее чем RSA-2048)

**ML-DSA-65 (Dilithium3)**:
- Стандартизован NIST (FIPS 204)
- Безопасность: эквивалентна AES-192
- Размеры: public key 1952 bytes, signature 3293 bytes
- Производительность: быстрая верификация

**Альтернативы** (для будущего):
- ML-KEM-1024 (Kyber1024) - безопасность AES-256 (для параноиков)
- SLH-DSA (SPHINCS+) - stateless hash-based подписи (backup для Dilithium)

## Архитектура Hybrid Suite

### CryptoProvider для Hybrid

```rust
// packages/core/src/crypto/suites/hybrid.rs

use crate::crypto::provider::CryptoProvider;
use crate::crypto::suites::classic::ClassicSuiteProvider;

/// Hybrid криптографический набор: Classical + Post-Quantum
///
/// Безопасность = MIN(Classical, PQ)
/// Если один алгоритм сломан, остаётся защита другого
pub struct HybridSuiteProvider;

impl CryptoProvider for HybridSuiteProvider {
    const SUITE_ID: u16 = 2; // Classic = 1, Hybrid = 2

    // === KEM (Key Exchange) ===
    // Hybrid = X25519 + ML-KEM-768

    type KemPrivateKey = HybridKemPrivateKey;
    type KemPublicKey = HybridKemPublicKey;

    fn generate_kem_keys() -> Result<(Self::KemPrivateKey, Self::KemPublicKey), CryptoError> {
        // Генерируем оба ключа
        let (x25519_priv, x25519_pub) = ClassicSuiteProvider::generate_kem_keys()?;
        let (mlkem_priv, mlkem_pub) = mlkem768::keypair();

        Ok((
            HybridKemPrivateKey {
                classical: x25519_priv,
                pq: mlkem_priv,
            },
            HybridKemPublicKey {
                classical: x25519_pub,
                pq: mlkem_pub,
            },
        ))
    }

    fn kem_decapsulate(private_key: &Self::KemPrivateKey, public_key: &[u8]) -> Result<Vec<u8>, CryptoError> {
        // Парсим hybrid public key
        let (classical_pk, pq_pk) = parse_hybrid_public_key(public_key)?;

        // Выполняем оба DH
        let classical_secret = x25519_dalek::x25519(
            private_key.classical.to_bytes(),
            classical_pk,
        );

        let pq_secret = mlkem768::decapsulate(&pq_pk, &private_key.pq);

        // Комбинируем секреты: HKDF(classical || pq)
        let combined = [&classical_secret[..], &pq_secret[..]].concat();

        Ok(combined)
    }

    // === Signatures ===
    // Hybrid = Ed25519 + ML-DSA-65

    type SignaturePrivateKey = HybridSignaturePrivateKey;
    type SignaturePublicKey = HybridSignaturePublicKey;

    fn generate_signature_keys() -> Result<(Self::SignaturePrivateKey, Self::SignaturePublicKey), CryptoError> {
        let (ed25519_priv, ed25519_pub) = ClassicSuiteProvider::generate_signature_keys()?;
        let (mldsa_priv, mldsa_pub) = mldsa65::keypair();

        Ok((
            HybridSignaturePrivateKey {
                classical: ed25519_priv,
                pq: mldsa_priv,
            },
            HybridSignaturePublicKey {
                classical: ed25519_pub,
                pq: mldsa_pub,
            },
        ))
    }

    fn sign(private_key: &Self::SignaturePrivateKey, message: &[u8]) -> Result<Vec<u8>, CryptoError> {
        // Создаём обе подписи
        let classical_sig = ed25519_dalek::sign(&private_key.classical, message);
        let pq_sig = mldsa65::sign(&private_key.pq, message);

        // Комбинируем: classical_sig || pq_sig
        let combined = [&classical_sig[..], &pq_sig[..]].concat();

        Ok(combined)
    }

    fn verify(public_key: &Self::SignaturePublicKey, message: &[u8], signature: &[u8]) -> Result<(), CryptoError> {
        // Парсим hybrid подпись
        let (classical_sig, pq_sig) = parse_hybrid_signature(signature)?;

        // Проверяем ОБЕ подписи (AND, не OR!)
        ed25519_dalek::verify(&public_key.classical, message, &classical_sig)?;
        mldsa65::verify(&public_key.pq, message, &pq_sig)?;

        Ok(())
    }

    // AEAD и KDF остаются как у Classical (они квантово-безопасны)
    type AeadKey = Vec<u8>;

    fn aead_encrypt(key: &Self::AeadKey, nonce: &[u8], plaintext: &[u8], aad: &[u8]) -> Result<Vec<u8>, CryptoError> {
        ClassicSuiteProvider::aead_encrypt(key, nonce, plaintext, aad)
    }

    fn aead_decrypt(key: &Self::AeadKey, nonce: &[u8], ciphertext: &[u8], aad: &[u8]) -> Result<Vec<u8>, CryptoError> {
        ClassicSuiteProvider::aead_decrypt(key, nonce, ciphertext, aad)
    }

    fn hkdf_derive_key(salt: &[u8], ikm: &[u8], info: &[u8], length: usize) -> Result<Vec<u8>, CryptoError> {
        ClassicSuiteProvider::hkdf_derive_key(salt, ikm, info, length)
    }
}

// === Типы ключей ===

#[derive(Clone)]
pub struct HybridKemPrivateKey {
    classical: Vec<u8>,        // 32 bytes X25519
    pq: mlkem768::SecretKey,   // 2400 bytes ML-KEM-768
}

#[derive(Clone)]
pub struct HybridKemPublicKey {
    classical: Vec<u8>,        // 32 bytes X25519
    pq: mlkem768::PublicKey,   // 1184 bytes ML-KEM-768
}

#[derive(Clone)]
pub struct HybridSignaturePrivateKey {
    classical: Vec<u8>,        // 32 bytes Ed25519
    pq: mldsa65::SecretKey,    // ~4000 bytes ML-DSA-65
}

#[derive(Clone)]
pub struct HybridSignaturePublicKey {
    classical: Vec<u8>,        // 32 bytes Ed25519
    pq: mldsa65::PublicKey,    // 1952 bytes ML-DSA-65
}
```

## Wire Format для Hybrid Keys

### Registration Bundle (Classical vs Hybrid)

**Classical** (текущий):
```
RegistrationBundle {
    identity_public: [u8; 32],       // X25519
    signed_prekey_public: [u8; 32],  // X25519
    signature: [u8; 64],             // Ed25519
    verifying_key: [u8; 32],         // Ed25519
    suite_id: 1,
}
Total: ~160 bytes
```

**Hybrid** (будущий):
```
RegistrationBundle {
    identity_public: Vec<u8>,        // 32 + 1184 = 1216 bytes
    signed_prekey_public: Vec<u8>,   // 32 + 1184 = 1216 bytes
    signature: Vec<u8>,              // 64 + 3293 = 3357 bytes
    verifying_key: Vec<u8>,          // 32 + 1952 = 1984 bytes
    suite_id: 2,
}
Total: ~7.7 KB
```

### Encoded Format

```
HybridKemPublicKey encoding:
[
    0x00, 0x20,                    // Classical length: 32 bytes
    <32 bytes X25519 public key>,
    0x04, 0xA0,                    // PQ length: 1184 bytes
    <1184 bytes ML-KEM-768 public key>
]

HybridSignature encoding:
[
    0x00, 0x40,                    // Classical length: 64 bytes
    <64 bytes Ed25519 signature>,
    0x0C, 0xDD,                    // PQ length: 3293 bytes
    <3293 bytes ML-DSA-65 signature>
]
```

## Hybrid X3DH Protocol

Полностью аналогичен классическому X3DH, но:

1. **3 DH операции** используют **hybrid KEM** вместо X25519
2. **Signature verification** проверяет **обе** подписи (Ed25519 AND ML-DSA-65)
3. **Секреты комбинируются**: `HKDF(classical_secret || pq_secret)`

```rust
// Alice performs hybrid X3DH
pub fn perform_x3dh_hybrid(
    alice_identity: &HybridKemPrivateKey,
    alice_ephemeral: &HybridKemPrivateKey,
    bob_identity_pub: &HybridKemPublicKey,
    bob_signed_prekey_pub: &HybridKemPublicKey,
    bob_signature: &[u8],
    bob_verifying_key: &HybridSignaturePublicKey,
) -> Result<Vec<u8>, String> {
    // 1. Verify signature (both classical and PQ)
    HybridSuiteProvider::verify(bob_verifying_key, bob_signed_prekey_pub.as_bytes(), bob_signature)?;

    // 2. Perform 3 hybrid DH operations
    let dh1 = hybrid_dh(&alice_identity, &bob_signed_prekey_pub)?;       // IK_A × SPK_B (both)
    let dh2 = hybrid_dh(&alice_ephemeral, &bob_identity_pub)?;           // EK_A × IK_B (both)
    let dh3 = hybrid_dh(&alice_ephemeral, &bob_signed_prekey_pub)?;      // EK_A × SPK_B (both)

    // 3. Combine all secrets
    let combined = [&dh1[..], &dh2[..], &dh3[..]].concat();

    // 4. Derive root key
    let root_key = HybridSuiteProvider::hkdf_derive_key(b"", &combined, b"X3DH Root Key", 32)?;

    Ok(root_key)
}

fn hybrid_dh(
    private_key: &HybridKemPrivateKey,
    public_key: &HybridKemPublicKey,
) -> Result<Vec<u8>, String> {
    // Classical X25519 DH
    let classical_secret = x25519_dalek::x25519(
        private_key.classical.as_bytes(),
        public_key.classical.as_bytes(),
    );

    // PQ ML-KEM-768 encapsulation
    // Note: В X3DH нам нужен симметричный DH, но ML-KEM - это KEM (asymmetric)
    // Используем подход из Internet-Draft: draft-ietf-tls-hybrid-design
    let pq_secret = mlkem768::encapsulate(&public_key.pq, &private_key.pq.derive_shared());

    // Combine: classical || pq
    Ok([&classical_secret[..], &pq_secret[..]].concat())
}
```

## Hybrid Double Ratchet

Double Ratchet остаётся **идентичным**, но:

1. **DH ratchet keys** используют `HybridKemPrivateKey` вместо `X25519PrivateKey`
2. **KDF operations** комбинируют classical и PQ секреты
3. **AEAD** остаётся ChaCha20-Poly1305 (квантово-безопасный)

Никаких изменений в логике Double Ratchet!

## Migration Path: Classical → Hybrid

### Фаза 1: Crypto-Agility (✅ Сейчас)
```rust
// Generic over CryptoProvider
pub struct Client<P: CryptoProvider, H: KeyAgreement<P>, M: SecureMessaging<P>> {
    ...
}

// Classical client
type ClassicClient = Client<
    ClassicSuiteProvider,
    X3DHProtocol<ClassicSuiteProvider>,
    DoubleRatchetProtocol<ClassicSuiteProvider>
>;
```

### Фаза 2: Hybrid Implementation (Q2 2026)
```rust
// Hybrid client
type HybridClient = Client<
    HybridSuiteProvider,  // ← New!
    X3DHProtocol<HybridSuiteProvider>,
    DoubleRatchetProtocol<HybridSuiteProvider>
>;
```

### Фаза 3: Mixed Protocol Support (Q3 2026)

Поддержка обоих протоколов одновременно:

```rust
// Server хранит оба bundle для каждого пользователя
UserKeyBundles {
    classical_bundle: RegistrationBundle<ClassicSuiteProvider>,
    hybrid_bundle: RegistrationBundle<HybridSuiteProvider>,
}

// Клиент выбирает протокол при инициации сессии
pub fn initiate_session_with_suite(
    &mut self,
    contact_id: &str,
    preferred_suite: SuiteID,
    remote_bundles: &UserKeyBundles,
) -> Result<String, String> {
    match preferred_suite {
        1 => self.initiate_classical_session(contact_id, &remote_bundles.classical_bundle),
        2 => self.initiate_hybrid_session(contact_id, &remote_bundles.hybrid_bundle),
        _ => Err("Unsupported suite".to_string()),
    }
}
```

### Фаза 4: Full Hybrid Rollout (Q4 2026)

- Все новые клиенты используют Hybrid
- Classical поддерживается для обратной совместимости
- Постепенная миграция существующих пользователей

## Security Analysis

### Threat Model

**Квантовый компьютер** достаточно мощный для:
- Алгоритм Шора: Взлом RSA, DH, ECDH, ECDSA
- Алгоритм Гровера: Ускорение brute-force в √N раз

**Защита**:
- ML-KEM-768: Устойчив к алгоритму Шора
- ML-DSA-65: Устойчив к алгоритму Шора
- ChaCha20: Устойчив к Гровера (256-bit → эффективно 128-bit, что достаточно)

### Security Properties

**Confidentiality**:
```
Атакующий должен взломать ОБА:
- X25519 (требует квантовый компьютер)
- ML-KEM-768 (требует взлом lattice-based crypto)

Security = MIN(128-bit classical, 192-bit PQ) = 128-bit
```

**Authentication**:
```
Атакующий должен подделать ОБЕ подписи:
- Ed25519 (требует квантовый компьютер)
- ML-DSA-65 (требует взлом lattice-based signatures)

Security = MIN(128-bit classical, 192-bit PQ) = 128-bit
```

**Forward Secrecy**: Сохраняется благодаря Double Ratchet (не зависит от suite)

**Break-in Recovery**: Сохраняется благодаря Double Ratchet (не зависит от suite)

## Implementation Checklist

### ✅ Crypto Primitives
- [ ] Интегрировать `pqcrypto-kyber` (ML-KEM-768)
- [ ] Интегрировать `pqcrypto-dilithium` (ML-DSA-65)
- [ ] Реализовать `HybridSuiteProvider`
- [ ] Реализовать hybrid key encoding/decoding
- [ ] Тесты: hybrid KEM correctness
- [ ] Тесты: hybrid signatures correctness

### ✅ X3DH Protocol
- [ ] Адаптировать `X3DHProtocol` для hybrid keys
- [ ] Реализовать hybrid DH operations
- [ ] Тесты: Alice и Bob получают одинаковый root key
- [ ] Тесты: Signature verification (оба алгоритма)

### ✅ Double Ratchet
- [ ] Проверить что Double Ratchet generic over P
- [ ] Тесты: Full roundtrip с HybridSuiteProvider
- [ ] Тесты: DH ratchet с hybrid keys

### ✅ Client API
- [ ] Создать type alias `HybridClient`
- [ ] Тесты: End-to-end flow с hybrid suite

### ✅ Wire Protocol
- [ ] Определить encoding для hybrid keys
- [ ] Обновить `RegistrationBundle` для suite_id=2
- [ ] Обновить `EncryptedMessage` (без изменений, только dh_public_key больше)

### ✅ Performance
- [ ] Benchmark: Classical vs Hybrid keygen
- [ ] Benchmark: Classical vs Hybrid X3DH
- [ ] Benchmark: Classical vs Hybrid signing/verification
- [ ] Оптимизация: Кэширование hybrid keys

## Dependencies

```toml
[dependencies]
# Classical (existing)
x25519-dalek = "2.0"
ed25519-dalek = "2.0"
chacha20poly1305 = "0.10"
hkdf = "0.12"
sha2 = "0.10"

# Post-Quantum (new)
pqcrypto-kyber = "0.8"      # ML-KEM (Kyber)
pqcrypto-dilithium = "0.5"  # ML-DSA (Dilithium)

[features]
default = ["classic"]
classic = []
hybrid = ["pqcrypto-kyber", "pqcrypto-dilithium"]
```

## Performance Expectations

### Key Generation (Classical vs Hybrid)

| Operation | Classical | Hybrid | Overhead |
|-----------|-----------|--------|----------|
| KEM keygen | 0.05 ms | 0.15 ms | 3x |
| Signature keygen | 0.03 ms | 0.5 ms | 17x |
| Total registration | 0.08 ms | 0.65 ms | 8x |

### X3DH Handshake

| Operation | Classical | Hybrid | Overhead |
|-----------|-----------|--------|----------|
| Sign SPK | 0.02 ms | 0.8 ms | 40x |
| Verify SPK | 0.03 ms | 1.2 ms | 40x |
| 3× DH | 0.15 ms | 0.45 ms | 3x |
| Total X3DH | 0.2 ms | 2.5 ms | 12.5x |

### Message Encryption (Double Ratchet)

| Operation | Classical | Hybrid | Overhead |
|-----------|-----------|--------|----------|
| DH ratchet step | 0.05 ms | 0.15 ms | 3x |
| AEAD encrypt | 0.01 ms | 0.01 ms | 1x |
| Total encrypt | 0.06 ms | 0.16 ms | 2.7x |

**Вывод**: Hybrid медленнее в 3-12x, но всё ещё **приемлемо** для мессенджера.

## Bandwidth Impact

### Registration Bundle Size

| Suite | Identity PK | SPK PK | Signature | Verifying Key | Total |
|-------|-------------|--------|-----------|---------------|-------|
| Classical | 32 B | 32 B | 64 B | 32 B | **160 B** |
| Hybrid | 1216 B | 1216 B | 3357 B | 1984 B | **7773 B** |

**Overhead**: ~48x больше

### First Message Size

| Suite | DH Public | Nonce | Ciphertext+Tag | Total |
|-------|-----------|-------|----------------|-------|
| Classical | 32 B | 12 B | n+16 B | **60+n B** |
| Hybrid | 1216 B | 12 B | n+16 B | **1244+n B** |

**Overhead**: ~20x больше для metadata, но растёт медленнее с размером сообщения

## Резюме

**Hybrid = Best of Both Worlds**:
- Защита от квантовых компьютеров (ML-KEM + ML-DSA)
- Сохранение classical security (X25519 + Ed25519)
- Graceful degradation: если один сломан, остаётся другой

**Стратегия**:
1. ✅ **Сейчас**: Crypto-agility через CryptoProvider trait
2. ⏳ **Q2 2026**: Реализация HybridSuiteProvider
3. ⏳ **Q3 2026**: Mixed protocol support (classical + hybrid)
4. ⏳ **Q4 2026**: Full hybrid rollout

**Цена**:
- Производительность: 3-12x медленнее
- Bandwidth: 20-48x больше
- **Выгода**: Защита на следующие 20+ лет
