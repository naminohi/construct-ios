# Стратегия тестирования криптографии

## Цель
Тесты должны **отражать реальный протокол**, а не просто проверять отдельные функции.

## Проблема с текущими тестами

Многие тесты генерируют "фейковые" ключи и не отражают реальный flow:

```rust
// ❌ ПЛОХО: Не отражает протокол
#[test]
fn test_double_ratchet_full_roundtrip() {
    let root_key = vec![42u8; 32];  // ← Взято из воздуха, не из X3DH

    let mut alice = DoubleRatchet::new(root_key, ...);
    let mut bob = DoubleRatchet::new(root_key, ...);  // ← Как Bob получил тот же root_key?

    let encrypted = alice.encrypt(b"hello");
    let decrypted = bob.decrypt(encrypted);  // ← Работает, но не реалистично
}
```

## Правильная стратегия

### Уровень 1: Unit тесты криптографических примитивов
**Цель**: Проверить корректность низкоуровневых операций

```rust
#[cfg(test)]
mod crypto_primitives {
    use crate::crypto::suites::classic::ClassicSuiteProvider;
    use crate::crypto::provider::CryptoProvider;

    #[test]
    fn test_kem_diffie_hellman_agreement() {
        // Проверяем что DH(a, B) = DH(b, A)
        let (alice_priv, alice_pub) = ClassicSuiteProvider::generate_kem_keys().unwrap();
        let (bob_priv, bob_pub) = ClassicSuiteProvider::generate_kem_keys().unwrap();

        let shared_alice = ClassicSuiteProvider::kem_decapsulate(&alice_priv, bob_pub.as_ref()).unwrap();
        let shared_bob = ClassicSuiteProvider::kem_decapsulate(&bob_priv, alice_pub.as_ref()).unwrap();

        assert_eq!(shared_alice, shared_bob, "DH shared secrets must match");
    }

    #[test]
    fn test_signature_verification() {
        let (signing_key, verifying_key) = ClassicSuiteProvider::generate_signature_keys().unwrap();
        let message = b"test message";

        let signature = ClassicSuiteProvider::sign(&signing_key, message).unwrap();

        // Positive case
        assert!(ClassicSuiteProvider::verify(&verifying_key, message, &signature).is_ok());

        // Negative case
        assert!(ClassicSuiteProvider::verify(&verifying_key, b"wrong message", &signature).is_err());
    }

    #[test]
    fn test_aead_encrypt_decrypt() {
        let key = vec![0x42; 32];
        let aead_key = ClassicSuiteProvider::aead_key_from_bytes(key).unwrap();
        let nonce = vec![0x11; 12];
        let plaintext = b"secret message";
        let aad = b"additional data";

        let ciphertext = ClassicSuiteProvider::aead_encrypt(&aead_key, &nonce, plaintext, aad).unwrap();
        let decrypted = ClassicSuiteProvider::aead_decrypt(&aead_key, &nonce, &ciphertext, aad).unwrap();

        assert_eq!(decrypted, plaintext);
    }

    #[test]
    fn test_hkdf_deterministic() {
        let salt = b"salt";
        let ikm = b"input key material";
        let info = b"context";

        let key1 = ClassicSuiteProvider::hkdf_derive_key(salt, ikm, info, 32).unwrap();
        let key2 = ClassicSuiteProvider::hkdf_derive_key(salt, ikm, info, 32).unwrap();

        assert_eq!(key1, key2, "HKDF must be deterministic");
    }
}
```

### Уровень 2: Protocol тесты (X3DH)
**Цель**: Проверить корректность handshake протокола

```rust
#[cfg(test)]
mod x3dh_protocol {
    use crate::crypto::handshake::x3dh::X3DHProtocol;
    use crate::crypto::handshake::KeyAgreement;
    use crate::crypto::suites::classic::ClassicSuiteProvider;

    /// Тест полного X3DH handshake: Alice и Bob должны получить одинаковый root key
    #[test]
    fn test_x3dh_full_handshake() {
        // === BOB РЕГИСТРИРУЕТСЯ ===
        let bob_bundle = X3DHProtocol::<ClassicSuiteProvider>::generate_registration_bundle().unwrap();

        // Сервер сохраняет bob_bundle (IK_pub, SPK_pub, signature, verifying_key)

        // === ALICE ИНИЦИИРУЕТ СЕССИЮ ===

        // Alice генерирует свои долгосрочные ключи
        let (alice_identity_priv, _) = ClassicSuiteProvider::generate_kem_keys().unwrap();

        // Alice выполняет X3DH как инициатор
        let (alice_root_key, alice_state) = X3DHProtocol::<ClassicSuiteProvider>::perform_as_initiator(
            &alice_identity_priv,
            &bob_bundle.public_bundle,
        ).unwrap();

        // Alice отправляет первое сообщение с ephemeral public key
        let alice_ephemeral_pub = ClassicSuiteProvider::from_private_key_to_public_key(
            &alice_state.ephemeral_private
        ).unwrap();

        // === BOB ПОЛУЧАЕТ ПЕРВОЕ СООБЩЕНИЕ ===

        // Bob получает Alice's identity public key от сервера
        let alice_identity_pub = ClassicSuiteProvider::from_private_key_to_public_key(
            &alice_identity_priv
        ).unwrap();

        // Bob выполняет X3DH как получатель
        let bob_root_key = X3DHProtocol::<ClassicSuiteProvider>::perform_as_responder(
            &bob_bundle.identity_private,
            &bob_bundle.signed_prekey_private,
            &alice_identity_pub,
            &alice_ephemeral_pub,
        ).unwrap();

        // === ПРОВЕРКА: Alice и Bob должны получить ОДИНАКОВЫЙ root key ===
        assert_eq!(
            alice_root_key, bob_root_key,
            "X3DH must produce same root key for Alice and Bob"
        );
    }

    /// Тест проверки подписи: Alice должна отклонить невалидную подпись
    #[test]
    fn test_x3dh_rejects_invalid_signature() {
        let bob_bundle = X3DHProtocol::<ClassicSuiteProvider>::generate_registration_bundle().unwrap();
        let (alice_identity_priv, _) = ClassicSuiteProvider::generate_kem_keys().unwrap();

        // Подменяем подпись на невалидную
        let mut malicious_bundle = bob_bundle.public_bundle.clone();
        malicious_bundle.signature = vec![0xFF; 64];

        // Alice должна отклонить
        let result = X3DHProtocol::<ClassicSuiteProvider>::perform_as_initiator(
            &alice_identity_priv,
            &malicious_bundle,
        );

        assert!(result.is_err(), "X3DH must reject invalid signature");
        assert!(result.unwrap_err().contains("Signature verification failed"));
    }
}
```

### Уровень 3: Messaging тесты (Double Ratchet)
**Цель**: Проверить корректность обмена сообщениями

```rust
#[cfg(test)]
mod double_ratchet_protocol {
    use crate::crypto::messaging::double_ratchet::DoubleRatchetProtocol;
    use crate::crypto::messaging::SecureMessaging;
    use crate::crypto::suites::classic::ClassicSuiteProvider;

    /// Тест полного roundtrip: Alice → Bob → Alice
    #[test]
    fn test_double_ratchet_bidirectional() {
        // Предполагаем, что X3DH уже выполнен
        let root_key = vec![0x42; 32];  // От X3DH

        // Alice создаёт initiator session с ephemeral key от X3DH
        let (alice_ephemeral_priv, _) = ClassicSuiteProvider::generate_kem_keys().unwrap();
        let (_, bob_identity_pub) = ClassicSuiteProvider::generate_kem_keys().unwrap();

        let initiator_state = InitiatorState {
            ephemeral_private: alice_ephemeral_priv,
        };

        let mut alice_session = DoubleRatchetProtocol::<ClassicSuiteProvider>::new_initiator_session(
            &root_key,
            initiator_state,
            &bob_identity_pub,
            "bob".to_string(),
        ).unwrap();

        // Alice отправляет первое сообщение
        let msg1 = alice_session.encrypt(b"Hello Bob").unwrap();

        // Bob создаёт responder session
        let (bob_identity_priv, _) = ClassicSuiteProvider::generate_kem_keys().unwrap();

        let mut bob_session = DoubleRatchetProtocol::<ClassicSuiteProvider>::new_responder_session(
            &root_key,
            &bob_identity_priv,
            &msg1,
            "alice".to_string(),
        ).unwrap();

        // Bob расшифровывает
        let decrypted1 = bob_session.decrypt(&msg1).unwrap();
        assert_eq!(decrypted1, b"Hello Bob");

        // Bob отвечает
        let msg2 = bob_session.encrypt(b"Hi Alice").unwrap();

        // Alice расшифровывает ответ
        let decrypted2 = alice_session.decrypt(&msg2).unwrap();
        assert_eq!(decrypted2, b"Hi Alice");

        // Alice отвечает снова (DH ratchet step)
        let msg3 = alice_session.encrypt(b"How are you?").unwrap();
        let decrypted3 = bob_session.decrypt(&msg3).unwrap();
        assert_eq!(decrypted3, b"How are you?");
    }

    /// Тест out-of-order сообщений
    #[test]
    fn test_double_ratchet_out_of_order() {
        // Setup как выше...

        // Alice отправляет 3 сообщения подряд
        let msg1 = alice_session.encrypt(b"Message 1").unwrap();
        let msg2 = alice_session.encrypt(b"Message 2").unwrap();
        let msg3 = alice_session.encrypt(b"Message 3").unwrap();

        // Bob получает в неправильном порядке: msg3, msg1, msg2
        let dec3 = bob_session.decrypt(&msg3).unwrap();
        assert_eq!(dec3, b"Message 3");

        let dec1 = bob_session.decrypt(&msg1).unwrap();
        assert_eq!(dec1, b"Message 1");

        let dec2 = bob_session.decrypt(&msg2).unwrap();
        assert_eq!(dec2, b"Message 2");
    }

    /// Тест защиты от DoS (MAX_SKIPPED_MESSAGES)
    #[test]
    fn test_double_ratchet_dos_protection() {
        // Setup...

        // Alice отправляет MAX_SKIPPED_MESSAGES + 1 сообщений
        let mut messages = vec![];
        for i in 0..1001 {
            messages.push(alice_session.encrypt(format!("Msg {}", i).as_bytes()).unwrap());
        }

        // Bob пытается расшифровать последнее сообщение
        let result = bob_session.decrypt(messages.last().unwrap());

        assert!(result.is_err(), "Must reject message with too many skips");
    }

    /// Тест cleanup старых skipped keys
    #[test]
    fn test_skipped_keys_cleanup() {
        // Setup...

        // Alice отправляет msg0, msg1, msg2
        let msg0 = alice_session.encrypt(b"0").unwrap();
        let msg1 = alice_session.encrypt(b"1").unwrap();
        let msg2 = alice_session.encrypt(b"2").unwrap();

        // Bob получает msg2 (skips msg0, msg1)
        bob_session.decrypt(&msg2).unwrap();

        // Проверяем что skipped keys сохранились
        assert_eq!(bob_session.skipped_message_keys_count(), 2);

        // Ждём (симулируем время)
        std::thread::sleep(std::time::Duration::from_secs(1));

        // Cleanup с коротким max_age
        bob_session.cleanup_old_skipped_keys(0);

        // Skipped keys должны быть удалены
        assert_eq!(bob_session.skipped_message_keys_count(), 0);
    }
}
```

### Уровень 4: Integration тесты (полный flow)
**Цель**: Проверить весь протокол end-to-end как в реальном приложении

```rust
#[cfg(test)]
mod end_to_end_integration {
    use crate::crypto::client::Client;
    use crate::crypto::handshake::x3dh::X3DHProtocol;
    use crate::crypto::messaging::double_ratchet::DoubleRatchetProtocol;
    use crate::crypto::suites::classic::ClassicSuiteProvider;

    /// Полный тест: регистрация → handshake → обмен сообщениями
    #[test]
    fn test_full_protocol_alice_to_bob() {
        // === РЕГИСТРАЦИЯ ===

        // Alice регистрируется
        let mut alice = Client::<
            ClassicSuiteProvider,
            X3DHProtocol<ClassicSuiteProvider>,
            DoubleRatchetProtocol<ClassicSuiteProvider>
        >::new().unwrap();

        let alice_bundle = alice.export_registration_bundle();
        // alice_bundle → Server

        // Bob регистрируется
        let mut bob = Client::<
            ClassicSuiteProvider,
            X3DHProtocol<ClassicSuiteProvider>,
            DoubleRatchetProtocol<ClassicSuiteProvider>
        >::new().unwrap();

        let bob_bundle = bob.export_registration_bundle();
        // bob_bundle → Server

        // === ALICE ИНИЦИИРУЕТ СЕССИЮ С BOB ===

        // Alice получает bob_bundle от сервера
        let alice_session_id = alice.initiate_session("bob", &bob_bundle).unwrap();

        // Alice отправляет первое сообщение
        let encrypted_msg1 = alice.encrypt_message(&alice_session_id, b"Hello Bob!").unwrap();

        // === BOB ПОЛУЧАЕТ ПЕРВОЕ СООБЩЕНИЕ ===

        // Bob получает alice_bundle и encrypted_msg1 от сервера
        let bob_session_id = bob.receive_session("alice", &alice_bundle, &encrypted_msg1).unwrap();

        // Bob расшифровывает
        let decrypted_msg1 = bob.decrypt_message(&bob_session_id, &encrypted_msg1).unwrap();
        assert_eq!(decrypted_msg1, b"Hello Bob!");

        // === BIDIRECTIONAL ОБМЕН ===

        // Bob отвечает
        let encrypted_msg2 = bob.encrypt_message(&bob_session_id, b"Hi Alice!").unwrap();
        let decrypted_msg2 = alice.decrypt_message(&alice_session_id, &encrypted_msg2).unwrap();
        assert_eq!(decrypted_msg2, b"Hi Alice!");

        // Alice продолжает разговор
        let encrypted_msg3 = alice.encrypt_message(&alice_session_id, b"How are you?").unwrap();
        let decrypted_msg3 = bob.decrypt_message(&bob_session_id, &encrypted_msg3).unwrap();
        assert_eq!(decrypted_msg3, b"How are you?");
    }

    /// Тест множественных сессий (Alice с Bob и Charlie)
    #[test]
    fn test_multiple_sessions() {
        let mut alice = Client::new().unwrap();
        let mut bob = Client::new().unwrap();
        let mut charlie = Client::new().unwrap();

        let alice_bundle = alice.export_registration_bundle();
        let bob_bundle = bob.export_registration_bundle();
        let charlie_bundle = charlie.export_registration_bundle();

        // Alice → Bob
        let session_ab = alice.initiate_session("bob", &bob_bundle).unwrap();
        let msg_ab = alice.encrypt_message(&session_ab, b"Hello Bob").unwrap();

        // Alice → Charlie
        let session_ac = alice.initiate_session("charlie", &charlie_bundle).unwrap();
        let msg_ac = alice.encrypt_message(&session_ac, b"Hello Charlie").unwrap();

        // Bob получает
        let session_ba = bob.receive_session("alice", &alice_bundle, &msg_ab).unwrap();
        let dec_ab = bob.decrypt_message(&session_ba, &msg_ab).unwrap();
        assert_eq!(dec_ab, b"Hello Bob");

        // Charlie получает
        let session_ca = charlie.receive_session("alice", &alice_bundle, &msg_ac).unwrap();
        let dec_ac = charlie.decrypt_message(&session_ca, &msg_ac).unwrap();
        assert_eq!(dec_ac, b"Hello Charlie");

        // Проверяем что сессии изолированы
        assert_ne!(session_ab, session_ac);
    }

    /// Тест session persistence (serialize/deserialize)
    #[test]
    fn test_session_persistence() {
        let mut alice = Client::new().unwrap();
        let mut bob = Client::new().unwrap();

        let alice_bundle = alice.export_registration_bundle();
        let bob_bundle = bob.export_registration_bundle();

        // Создаём сессию и обмениваемся сообщениями
        let session_id = alice.initiate_session("bob", &bob_bundle).unwrap();
        let msg1 = alice.encrypt_message(&session_id, b"Message 1").unwrap();

        // Экспортируем сессию
        let session_data = alice.export_session(&session_id).unwrap();

        // Создаём нового клиента и восстанавливаем сессию
        let mut alice_new = Client::new().unwrap();
        let restored_session_id = alice_new.restore_session(&session_data).unwrap();

        // Должны продолжить работу с той же сессией
        let msg2 = alice_new.encrypt_message(&restored_session_id, b"Message 2").unwrap();

        // message_number должен увеличиться
        assert!(msg2.message_number > msg1.message_number);
    }
}
```

### Уровень 5: Security тесты
**Цель**: Проверить security properties

```rust
#[cfg(test)]
mod security_tests {
    /// Тест forward secrecy: компрометация текущего ключа не раскрывает прошлые сообщения
    #[test]
    fn test_forward_secrecy() {
        // Setup сессии
        // Alice отправляет 5 сообщений
        let messages: Vec<_> = (0..5)
            .map(|i| alice.encrypt_message(&session_id, format!("Msg {}", i).as_bytes()).unwrap())
            .collect();

        // Сохраняем текущее состояние Alice (компрометация)
        let compromised_state = alice.export_session(&session_id).unwrap();

        // Атакующий пытается расшифровать старые сообщения с compromised state
        let mut attacker = Client::new().unwrap();
        let attacker_session = attacker.restore_session(&compromised_state).unwrap();

        // Старые сообщения НЕ должны расшифроваться
        for msg in &messages[0..4] {
            let result = attacker.decrypt_message(&attacker_session, msg);
            assert!(result.is_err(), "Forward secrecy violated: old messages decrypted");
        }
    }

    /// Тест break-in recovery: компрометация ключа + новый обмен = восстановление безопасности
    #[test]
    fn test_break_in_recovery() {
        // Setup и обмен сообщениями
        // ... Alice и Bob обмениваются сообщениями ...

        // Компрометация состояния Bob
        let compromised_state = bob.export_session(&session_id).unwrap();

        // Alice и Bob продолжают обмен (DH ratchet)
        let new_msg_alice = alice.encrypt_message(&session_id, b"After compromise").unwrap();
        bob.decrypt_message(&session_id, &new_msg_alice).unwrap();

        let new_msg_bob = bob.encrypt_message(&session_id, b"Recovery").unwrap();

        // Атакующий с compromised state НЕ должен расшифровать новые сообщения
        let mut attacker = Client::new().unwrap();
        let attacker_session = attacker.restore_session(&compromised_state).unwrap();

        let result = attacker.decrypt_message(&attacker_session, &new_msg_bob);
        assert!(result.is_err(), "Break-in recovery failed: new messages decrypted");
    }

    /// Тест replay attack protection
    #[test]
    fn test_replay_attack_protection() {
        // Alice отправляет сообщение
        let msg = alice.encrypt_message(&session_id, b"Transfer $100").unwrap();

        // Bob получает и обрабатывает
        let dec1 = bob.decrypt_message(&session_id, &msg).unwrap();
        assert_eq!(dec1, b"Transfer $100");

        // Атакующий пытается replay то же сообщение
        let result = bob.decrypt_message(&session_id, &msg);
        assert!(result.is_err(), "Replay attack not prevented");
    }
}
```

## Структура тестов

```
packages/core/tests/
├── crypto_primitives_test.rs     # Уровень 1: DH, AEAD, HKDF, signatures
├── x3dh_protocol_test.rs         # Уровень 2: X3DH handshake
├── double_ratchet_protocol_test.rs  # Уровень 3: Double Ratchet messaging
├── integration_test.rs           # Уровень 4: End-to-end flow
└── security_test.rs              # Уровень 5: Security properties
```

## Test Coverage цели

- **Crypto primitives**: 100% (все DH, AEAD, KDF операции)
- **X3DH protocol**: 100% (initiator, responder, signature verification)
- **Double Ratchet**: 100% (encrypt, decrypt, ratchet steps, out-of-order)
- **Client API**: 90%+ (все public методы)
- **Security properties**: Ключевые properties (forward secrecy, break-in recovery, replay protection)

## Checklist для каждого теста

### ✅ X3DH тесты должны проверять:
- [ ] Alice и Bob получают одинаковый root key
- [ ] Signature verification работает
- [ ] Invalid signature отклоняется
- [ ] Ephemeral key генерируется для каждой сессии
- [ ] Все 3 DH операции выполняются корректно

### ✅ Double Ratchet тесты должны проверять:
- [ ] Bidirectional обмен работает
- [ ] Out-of-order сообщения расшифровываются
- [ ] MAX_SKIPPED_MESSAGES не превышается
- [ ] Skipped keys cleanup работает
- [ ] DH ratchet step обновляет ключи
- [ ] Message numbers монотонно возрастают

### ✅ Integration тесты должны проверять:
- [ ] Полный flow: регистрация → handshake → messaging
- [ ] Множественные сессии изолированы
- [ ] Session persistence (serialize/deserialize)
- [ ] Error handling на каждом этапе

### ✅ Security тесты должны проверять:
- [ ] Forward secrecy (старые сообщения не расшифровываются)
- [ ] Break-in recovery (новые сообщения безопасны после компрометации)
- [ ] Replay attack protection
- [ ] Message integrity (tampering обнаруживается)

## Резюме

**Главный принцип**: Тесты должны отражать **реальный протокол flow**.

Не тестируйте функции изолированно - тестируйте **scenarios**:
- Alice регистрируется, Bob регистрируется
- Alice инициирует сессию с Bob
- Alice отправляет сообщение
- Bob получает и расшифровывает
- Bob отвечает
- ...

Каждый тест = **история использования** (user story) протокола.
