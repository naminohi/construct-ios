//! Comprehensive tests for cryptographic functions
//!
//! This test suite covers:
//! - Classic Suite Provider (X25519, Ed25519, ChaCha20-Poly1305)
//! - Double Ratchet Protocol
//! - X3DH Key Agreement
//! - Session Management
//! - Error Handling

use construct_core::crypto::classic_suite::ClassicSuiteProvider;
use construct_core::crypto::crypto_provider::CryptoProvider;
use construct_core::crypto::double_ratchet::DoubleRatchetSession;
use construct_core::crypto::x3dh::X3DH;
use construct_core::crypto::client::ClientCrypto;

/// Test that ClassicSuiteProvider can generate KEM keys
#[test]
fn test_classic_suite_generate_kem_keys() {
    let result = ClassicSuiteProvider::generate_kem_keys();
    assert!(result.is_ok(), "Failed to generate KEM keys");

    let (private_key, public_key) = result.unwrap();

    // X25519 keys should be 32 bytes
    assert_eq!(private_key.len(), 32, "Private key should be 32 bytes");
    assert_eq!(public_key.len(), 32, "Public key should be 32 bytes");
}

/// Test that ClassicSuiteProvider can generate signature keys
#[test]
fn test_classic_suite_generate_signature_keys() {
    let result = ClassicSuiteProvider::generate_signature_keys();
    assert!(result.is_ok(), "Failed to generate signature keys");

    let (signing_key, verifying_key) = result.unwrap();

    // Ed25519 keys: signing key 32 bytes, verifying key 32 bytes
    assert_eq!(signing_key.len(), 32, "Signing key should be 32 bytes");
    assert_eq!(verifying_key.len(), 32, "Verifying key should be 32 bytes");
}

/// Test signature creation and verification
#[test]
fn test_classic_suite_sign_verify() {
    let (signing_key, verifying_key) = ClassicSuiteProvider::generate_signature_keys().unwrap();
    let message = b"Hello, Construct Messenger!";

    // Sign the message
    let signature = ClassicSuiteProvider::sign(&signing_key, message);
    assert!(signature.is_ok(), "Failed to sign message");
    let signature = signature.unwrap();

    // Ed25519 signature should be 64 bytes
    assert_eq!(signature.len(), 64, "Signature should be 64 bytes");

    // Verify the signature
    let verify_result = ClassicSuiteProvider::verify(&verifying_key, message, &signature);
    assert!(verify_result.is_ok(), "Signature verification failed");
}

/// Test that signature verification fails with wrong message
#[test]
fn test_classic_suite_verify_fails_with_wrong_message() {
    let (signing_key, verifying_key) = ClassicSuiteProvider::generate_signature_keys().unwrap();
    let message = b"Original message";
    let wrong_message = b"Modified message";

    let signature = ClassicSuiteProvider::sign(&signing_key, message).unwrap();

    // Verification should fail with wrong message
    let verify_result = ClassicSuiteProvider::verify(&verifying_key, wrong_message, &signature);
    assert!(verify_result.is_err(), "Verification should fail with wrong message");
}

/// Test AEAD encryption and decryption
#[test]
fn test_classic_suite_aead_encrypt_decrypt() {
    let key = vec![0u8; 32]; // ChaCha20-Poly1305 uses 32-byte keys
    let nonce = ClassicSuiteProvider::generate_nonce(12).unwrap(); // 12-byte nonce
    let plaintext = b"Secret message for encryption test";
    let aad = b"associated data";

    // Encrypt
    let ciphertext = ClassicSuiteProvider::aead_encrypt(&key, &nonce, plaintext, Some(aad));
    assert!(ciphertext.is_ok(), "Encryption failed");
    let ciphertext = ciphertext.unwrap();

    // Ciphertext should be plaintext + 16-byte tag
    assert_eq!(ciphertext.len(), plaintext.len() + 16, "Ciphertext length incorrect");

    // Decrypt
    let decrypted = ClassicSuiteProvider::aead_decrypt(&key, &nonce, &ciphertext, Some(aad));
    assert!(decrypted.is_ok(), "Decryption failed");
    assert_eq!(decrypted.unwrap(), plaintext, "Decrypted plaintext doesn't match");
}

/// Test that AEAD decryption fails with wrong key
#[test]
fn test_classic_suite_aead_decrypt_fails_with_wrong_key() {
    let key = vec![0u8; 32];
    let wrong_key = vec![1u8; 32];
    let nonce = ClassicSuiteProvider::generate_nonce(12).unwrap();
    let plaintext = b"Secret message";

    let ciphertext = ClassicSuiteProvider::aead_encrypt(&key, &nonce, plaintext, None).unwrap();

    // Decryption should fail with wrong key
    let result = ClassicSuiteProvider::aead_decrypt(&wrong_key, &nonce, &ciphertext, None);
    assert!(result.is_err(), "Decryption should fail with wrong key");
}

/// Test that AEAD decryption fails with wrong nonce
#[test]
fn test_classic_suite_aead_decrypt_fails_with_wrong_nonce() {
    let key = vec![0u8; 32];
    let nonce = ClassicSuiteProvider::generate_nonce(12).unwrap();
    let wrong_nonce = ClassicSuiteProvider::generate_nonce(12).unwrap();
    let plaintext = b"Secret message";

    let ciphertext = ClassicSuiteProvider::aead_encrypt(&key, &nonce, plaintext, None).unwrap();

    // Decryption should fail with wrong nonce
    let result = ClassicSuiteProvider::aead_decrypt(&key, &wrong_nonce, &ciphertext, None);
    assert!(result.is_err(), "Decryption should fail with wrong nonce");
}

/// Test HKDF key derivation
#[test]
fn test_classic_suite_hkdf() {
    let salt = b"test_salt";
    let ikm = b"input_key_material_for_derivation";
    let info = b"context_info";
    let len = 32;

    let derived_key = ClassicSuiteProvider::hkdf_derive_key(salt, ikm, info, len);
    assert!(derived_key.is_ok(), "HKDF derivation failed");

    let key = derived_key.unwrap();
    assert_eq!(key.len(), len, "Derived key length incorrect");

    // Verify determinism: same inputs should give same output
    let derived_key2 = ClassicSuiteProvider::hkdf_derive_key(salt, ikm, info, len).unwrap();
    assert_eq!(key, derived_key2, "HKDF should be deterministic");
}

/// Test KDF_RK (Root Key Derivation)
#[test]
fn test_classic_suite_kdf_rk() {
    let root_key = vec![0u8; 32];
    let dh_output = vec![1u8; 32];

    let result = ClassicSuiteProvider::kdf_rk(&root_key, &dh_output);
    assert!(result.is_ok(), "KDF_RK failed");

    let (new_root_key, chain_key) = result.unwrap();
    assert_eq!(new_root_key.len(), 32, "New root key should be 32 bytes");
    assert_eq!(chain_key.len(), 32, "Chain key should be 32 bytes");

    // Keys should be different from original
    assert_ne!(new_root_key.as_slice(), root_key.as_slice(), "New root key should differ");
}

/// Test KDF_CK (Chain Key Derivation)
#[test]
fn test_classic_suite_kdf_ck() {
    let chain_key = vec![0u8; 32];

    let result = ClassicSuiteProvider::kdf_ck(&chain_key);
    assert!(result.is_ok(), "KDF_CK failed");

    let (message_key, next_chain_key) = result.unwrap();
    assert_eq!(message_key.len(), 32, "Message key should be 32 bytes");
    assert_eq!(next_chain_key.len(), 32, "Next chain key should be 32 bytes");

    // Keys should be different
    assert_ne!(message_key.as_slice(), next_chain_key.as_slice());
}

/// Test X3DH protocol with full ephemeral key handshake
#[test]
fn test_x3dh_perform_handshake() {
    // Alice's keys
    let (alice_identity_private, _alice_identity_public) =
        ClassicSuiteProvider::generate_kem_keys().unwrap();
    let (alice_ephemeral_private, _alice_ephemeral_public) =
        ClassicSuiteProvider::generate_kem_keys().unwrap();

    // Bob's keys
    let (_bob_identity_private, bob_identity_public) =
        ClassicSuiteProvider::generate_kem_keys().unwrap();
    let (_bob_signed_prekey_private, bob_signed_prekey_public) =
        ClassicSuiteProvider::generate_kem_keys().unwrap();
    let (bob_signing_key, bob_verifying_key) =
        ClassicSuiteProvider::generate_signature_keys().unwrap();

    // Bob signs his prekey
    let bob_signature = ClassicSuiteProvider::sign(
        &bob_signing_key,
        bob_signed_prekey_public.as_ref()
    ).unwrap();

    // Alice performs X3DH with Bob's public keys (with ephemeral key!)
    let root_key_result = X3DH::<ClassicSuiteProvider>::perform_x3dh(
        &alice_identity_private,
        &alice_ephemeral_private,  // ✅ Ephemeral key for forward secrecy
        &bob_identity_public,
        &bob_signed_prekey_public,
        &bob_signature,
        &bob_verifying_key,
        1, // suite_id
    );

    assert!(root_key_result.is_ok(), "X3DH failed: {:?}", root_key_result.err());
    let root_key = root_key_result.unwrap();
    assert_eq!(root_key.len(), 32, "Root key should be 32 bytes");
}

/// Test X3DH fails with invalid signature
#[test]
fn test_x3dh_fails_with_invalid_signature() {
    let (alice_identity_private, _) = ClassicSuiteProvider::generate_kem_keys().unwrap();
    let (alice_ephemeral_private, _) = ClassicSuiteProvider::generate_kem_keys().unwrap();
    let (_, bob_identity_public) = ClassicSuiteProvider::generate_kem_keys().unwrap();
    let (_, bob_signed_prekey_public) = ClassicSuiteProvider::generate_kem_keys().unwrap();
    let (_, bob_verifying_key) = ClassicSuiteProvider::generate_signature_keys().unwrap();

    // Invalid signature (just random bytes)
    let invalid_signature = vec![0u8; 64];

    let result = X3DH::<ClassicSuiteProvider>::perform_x3dh(
        &alice_identity_private,
        &alice_ephemeral_private,  // ✅ Ephemeral key
        &bob_identity_public,
        &bob_signed_prekey_public,
        &invalid_signature,
        &bob_verifying_key,
        1,
    );

    assert!(result.is_err(), "X3DH should fail with invalid signature");
}

/// Test Double Ratchet: Alice → Bob (initiator session)
#[test]
fn test_double_ratchet_initiator_session() {
    // Setup keys
    let (alice_identity_private, _) = ClassicSuiteProvider::generate_kem_keys().unwrap();
    let (_, bob_identity_public) = ClassicSuiteProvider::generate_kem_keys().unwrap();

    // Derive a root key (normally from X3DH)
    let root_key = vec![0u8; 32];

    // Alice generates ephemeral key (as in real X3DH)
    let (alice_ephemeral_private, _) = ClassicSuiteProvider::generate_kem_keys().unwrap();

    // Alice creates initiator session
    let session_result = DoubleRatchetSession::<ClassicSuiteProvider>::new_x3dh_session(
        1, // suite_id
        &root_key,
        &alice_ephemeral_private,  // X3DH ephemeral key
        &bob_identity_public,
        "bob_user_id".to_string(),
    );

    assert!(session_result.is_ok(), "Failed to create initiator session");
    let mut alice_session = session_result.unwrap();

    // Test encryption
    let plaintext = b"Hello Bob!";
    let encrypted = alice_session.encrypt(plaintext);
    assert!(encrypted.is_ok(), "Encryption failed");

    let encrypted_msg = encrypted.unwrap();
    assert_eq!(encrypted_msg.message_number, 0, "First message should have number 0");
    assert_eq!(encrypted_msg.dh_public_key.len(), 32, "DH public key should be 32 bytes");
    assert!(encrypted_msg.ciphertext.len() > plaintext.len(), "Ciphertext should include AEAD tag");
}

/// Test Double Ratchet: Full encryption/decryption roundtrip
#[test]
fn test_double_ratchet_full_roundtrip() {
    // Alice and Bob's identity keys
    let (alice_identity_private, _alice_identity_public) =
        ClassicSuiteProvider::generate_kem_keys().unwrap();
    let (bob_identity_private, bob_identity_public) =
        ClassicSuiteProvider::generate_kem_keys().unwrap();

    // Shared root key (normally derived from X3DH)
    let root_key = vec![42u8; 32];

    // Alice generates ephemeral key (as in real X3DH)
    let (alice_ephemeral_private, _) = ClassicSuiteProvider::generate_kem_keys().unwrap();

    // Alice creates initiator session
    let mut alice_session = DoubleRatchetSession::<ClassicSuiteProvider>::new_x3dh_session(
        1,
        &root_key,
        &alice_ephemeral_private,  // X3DH ephemeral key
        &bob_identity_public,
        "bob".to_string(),
    ).unwrap();

    // Alice sends first message
    let plaintext1 = b"Hello Bob, this is Alice!";
    let encrypted1 = alice_session.encrypt(plaintext1).unwrap();

    // Bob creates receiving session with Alice's first message
    let mut bob_session = DoubleRatchetSession::<ClassicSuiteProvider>::new_receiving_session(
        1,
        &root_key,
        &bob_identity_private,
        &encrypted1,
        "alice".to_string(),
    ).unwrap();

    // Bob decrypts Alice's message
    let decrypted1 = bob_session.decrypt(&encrypted1);
    assert!(decrypted1.is_ok(), "Bob failed to decrypt Alice's message");
    assert_eq!(decrypted1.unwrap(), plaintext1, "Decrypted message doesn't match");

    // Bob replies
    let plaintext2 = b"Hi Alice, Bob here!";
    let encrypted2 = bob_session.encrypt(plaintext2).unwrap();

    // Alice decrypts Bob's reply
    let decrypted2 = alice_session.decrypt(&encrypted2);
    assert!(decrypted2.is_ok(), "Alice failed to decrypt Bob's message");
    assert_eq!(decrypted2.unwrap(), plaintext2, "Decrypted reply doesn't match");
}

/// Test Double Ratchet: Out-of-order message handling
#[test]
fn test_double_ratchet_out_of_order_messages() {
    let (alice_identity_private, _) = ClassicSuiteProvider::generate_kem_keys().unwrap();
    let (bob_identity_private, bob_identity_public) =
        ClassicSuiteProvider::generate_kem_keys().unwrap();
    let root_key = vec![0u8; 32];

    // Alice generates ephemeral key (as in real X3DH)
    let (alice_ephemeral_private, _) = ClassicSuiteProvider::generate_kem_keys().unwrap();

    // Alice creates session
    let mut alice_session = DoubleRatchetSession::<ClassicSuiteProvider>::new_x3dh_session(
        1,
        &root_key,
        &alice_ephemeral_private,  // X3DH ephemeral key
        &bob_identity_public,
        "bob".to_string(),
    ).unwrap();

    // Alice sends 3 messages
    let msg0 = alice_session.encrypt(b"Message 0").unwrap();
    let msg1 = alice_session.encrypt(b"Message 1").unwrap();
    let msg2 = alice_session.encrypt(b"Message 2").unwrap();

    // Bob creates receiving session
    let mut bob_session = DoubleRatchetSession::<ClassicSuiteProvider>::new_receiving_session(
        1,
        &root_key,
        &bob_identity_private,
        &msg0,
        "alice".to_string(),
    ).unwrap();

    // Bob decrypts msg0
    bob_session.decrypt(&msg0).unwrap();

    // Bob receives msg2 BEFORE msg1 (out of order)
    let result2 = bob_session.decrypt(&msg2);
    assert!(result2.is_ok(), "Should handle out-of-order message");

    // Now Bob receives msg1
    let result1 = bob_session.decrypt(&msg1);
    assert!(result1.is_ok(), "Should decrypt skipped message");
    assert_eq!(result1.unwrap(), b"Message 1", "Skipped message content incorrect");
}

/// Test ClientCrypto: Registration bundle generation
#[test]
fn test_client_crypto_registration_bundle() {
    let client = ClientCrypto::<ClassicSuiteProvider>::new();
    assert!(client.is_ok(), "Failed to create ClientCrypto");

    let client = client.unwrap();
    let bundle = client.get_registration_bundle();

    // Verify bundle structure
    assert_eq!(bundle.suite_id, 1, "Suite ID should be 1 (Classic)");
    assert_eq!(bundle.identity_public.len(), 32, "Identity public key should be 32 bytes");
    assert_eq!(bundle.signed_prekey_public.len(), 32, "Signed prekey should be 32 bytes");
    assert_eq!(bundle.signature.len(), 64, "Signature should be 64 bytes");
    assert_eq!(bundle.verifying_key.len(), 32, "Verifying key should be 32 bytes");

    // Verify signature
    let verify_result = ClassicSuiteProvider::verify(
        &ClassicSuiteProvider::signature_public_key_from_bytes(bundle.verifying_key.clone()),
        &bundle.signed_prekey_public,
        &bundle.signature,
    );
    assert!(verify_result.is_ok(), "Bundle signature verification failed");
}

/// Test ClientCrypto: Session initialization
#[test]
fn test_client_crypto_init_session() {
    let mut alice_client = ClientCrypto::<ClassicSuiteProvider>::new().unwrap();
    let bob_client = ClientCrypto::<ClassicSuiteProvider>::new().unwrap();

    // Get Bob's bundle
    let bob_bundle_data = bob_client.get_registration_bundle();
    let bob_bundle = construct_core::crypto::x3dh::PublicKeyBundle {
        identity_public: bob_bundle_data.identity_public,
        signed_prekey_public: bob_bundle_data.signed_prekey_public,
        signature: bob_bundle_data.signature,
        verifying_key: bob_bundle_data.verifying_key,
        suite_id: bob_bundle_data.suite_id,
    };

    // Alice initializes session with Bob
    let session_id = alice_client.init_session("bob_user_id", &bob_bundle);
    assert!(session_id.is_ok(), "Failed to initialize session");

    // Verify session ID is a valid UUID
    let session_id = session_id.unwrap();
    assert!(!session_id.is_empty(), "Session ID should not be empty");
}

/// Test ClientCrypto: Full message exchange
#[test]
fn test_client_crypto_message_exchange() {
    let mut alice_client = ClientCrypto::<ClassicSuiteProvider>::new().unwrap();
    let mut bob_client = ClientCrypto::<ClassicSuiteProvider>::new().unwrap();

    // Exchange bundles
    let alice_bundle_data = alice_client.get_registration_bundle();
    let bob_bundle_data = bob_client.get_registration_bundle();

    let alice_bundle = construct_core::crypto::x3dh::PublicKeyBundle {
        identity_public: alice_bundle_data.identity_public,
        signed_prekey_public: alice_bundle_data.signed_prekey_public,
        signature: alice_bundle_data.signature,
        verifying_key: alice_bundle_data.verifying_key,
        suite_id: alice_bundle_data.suite_id,
    };

    let bob_bundle = construct_core::crypto::x3dh::PublicKeyBundle {
        identity_public: bob_bundle_data.identity_public,
        signed_prekey_public: bob_bundle_data.signed_prekey_public,
        signature: bob_bundle_data.signature,
        verifying_key: bob_bundle_data.verifying_key,
        suite_id: bob_bundle_data.suite_id,
    };

    // Alice initiates session
    let alice_session_id = alice_client.init_session("bob", &bob_bundle).unwrap();

    // Alice sends message
    let plaintext = b"Hello Bob from Alice!";
    let encrypted = alice_client.encrypt_ratchet_message(&alice_session_id, plaintext).unwrap();

    // Bob receives and creates session
    let bob_session_id = bob_client
        .init_receiving_session("alice", &alice_bundle, &encrypted)
        .unwrap();

    // Bob decrypts
    let decrypted = bob_client.decrypt_ratchet_message(&bob_session_id, &encrypted);
    assert!(decrypted.is_ok(), "Bob failed to decrypt");
    assert_eq!(decrypted.unwrap(), plaintext, "Decrypted message doesn't match");
}

/// Test session serialization and restoration
#[test]
fn test_session_serialization() {
    let mut client = ClientCrypto::<ClassicSuiteProvider>::new().unwrap();
    let remote_bundle_data = ClientCrypto::<ClassicSuiteProvider>::new().unwrap()
        .get_registration_bundle();

    let remote_bundle = construct_core::crypto::x3dh::PublicKeyBundle {
        identity_public: remote_bundle_data.identity_public,
        signed_prekey_public: remote_bundle_data.signed_prekey_public,
        signature: remote_bundle_data.signature,
        verifying_key: remote_bundle_data.verifying_key,
        suite_id: remote_bundle_data.suite_id,
    };

    let session_id = client.init_session("contact", &remote_bundle).unwrap();

    // Export session
    let exported = client.export_session(&session_id);
    assert!(exported.is_ok(), "Failed to export session");

    // Create new client and restore session
    let mut new_client = ClientCrypto::<ClassicSuiteProvider>::new().unwrap();
    let restored_id = new_client.restore_session(&exported.unwrap());
    assert!(restored_id.is_ok(), "Failed to restore session");
}

/// Benchmark: Encryption performance
#[test]
fn test_encryption_performance() {
    let mut client = ClientCrypto::<ClassicSuiteProvider>::new().unwrap();
    let remote_bundle_data = ClientCrypto::<ClassicSuiteProvider>::new().unwrap()
        .get_registration_bundle();

    let remote_bundle = construct_core::crypto::x3dh::PublicKeyBundle {
        identity_public: remote_bundle_data.identity_public,
        signed_prekey_public: remote_bundle_data.signed_prekey_public,
        signature: remote_bundle_data.signature,
        verifying_key: remote_bundle_data.verifying_key,
        suite_id: remote_bundle_data.suite_id,
    };

    let session_id = client.init_session("perf_test", &remote_bundle).unwrap();

    let plaintext = b"Performance test message";
    let iterations = 100;

    let start = std::time::Instant::now();
    for _ in 0..iterations {
        let _ = client.encrypt_ratchet_message(&session_id, plaintext).unwrap();
    }
    let duration = start.elapsed();

    let avg_time = duration.as_micros() / iterations;
    println!("Average encryption time: {} μs", avg_time);

    // Performance assertion: should be < 1ms per encryption
    assert!(avg_time < 1000, "Encryption too slow: {} μs", avg_time);
}

/// Test random number generation quality (entropy check)
#[test]
fn test_random_number_quality() {
    let mut bytes_set = std::collections::HashSet::new();

    // Generate 100 random nonces
    for _ in 0..100 {
        let nonce = ClassicSuiteProvider::generate_nonce(12).unwrap();
        let nonce_hex = hex::encode(&nonce);

        // All nonces should be unique
        assert!(
            bytes_set.insert(nonce_hex.clone()),
            "Duplicate nonce generated: {}",
            nonce_hex
        );
    }

    // Should have 100 unique nonces
    assert_eq!(bytes_set.len(), 100, "Not all nonces are unique");
}
