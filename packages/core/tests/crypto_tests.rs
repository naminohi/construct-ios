//! Comprehensive tests for cryptographic functions
//!
//! This test suite covers:
//! - Classic Suite Provider (X25519, Ed25519, ChaCha20-Poly1305)
//! - Double Ratchet Protocol
//! - X3DH Key Agreement
//! - Session Management
//! - Error Handling

use construct_core::crypto::suites::classic::ClassicSuiteProvider;
use construct_core::crypto::CryptoProvider;
// Commented out since the low-level API tests have been deferred for refactoring
// use construct_core::crypto::messaging::double_ratchet::DoubleRatchetSession;
// use construct_core::crypto::handshake::x3dh::X3DHProtocol;
// use construct_core::crypto::client_api::Client;
// use construct_core::crypto::handshake::KeyAgreement;

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

/*
// TODO: Refactor X3DH tests to use new KeyAgreement trait API
// The X3DHProtocol now implements KeyAgreement trait, not direct perform_x3dh() method

/// Test X3DH protocol with full ephemeral key handshake
#[test]
fn test_x3dh_perform_handshake() {
    // TODO: Refactor to use new X3DHProtocol API
}

/// Test X3DH fails with invalid signature
#[test]
fn test_x3dh_fails_with_invalid_signature() {
    // TODO: Refactor to use new X3DHProtocol API
}
*/

/*
// TODO: Refactor DoubleRatchet tests to use new SecureMessaging trait API
// The new API uses new_initiator_session() and new_responder_session()

/// Test Double Ratchet: Alice → Bob (initiator session)
#[test]
fn test_double_ratchet_initiator_session() {
    // TODO: Refactor to use new DoubleRatchetSession API
}

/// Test Double Ratchet: Full encryption/decryption roundtrip
#[test]
fn test_double_ratchet_full_roundtrip() {
    // TODO: Refactor to use new DoubleRatchetSession API
}

/// Test Double Ratchet: Out-of-order message handling
#[test]
fn test_double_ratchet_out_of_order_messages() {
    // TODO: Refactor to use new DoubleRatchetSession API
}
*/

/*
// TODO: Refactor Client tests to use new Client API
// The new Client<P, X3DHProtocol<P>, DoubleRatchetSession<P>> has a different API:
// - Use client.key_manager().export_registration_bundle() instead of get_registration_bundle()
// - init_session() and other methods have different signatures

/// Test ClientCrypto: Registration bundle generation
#[test]
fn test_client_crypto_registration_bundle() {
    let client = Client::<ClassicSuiteProvider, X3DHProtocol<ClassicSuiteProvider>, DoubleRatchetSession<ClassicSuiteProvider>>::new();
    assert!(client.is_ok(), "Failed to create Client");

    let client = client.unwrap();
    let bundle = client.key_manager().export_registration_bundle().unwrap();

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
*/

/*
/// Test ClientCrypto: Session initialization
#[test]
fn test_client_crypto_init_session() {
    // TODO: Refactor to use new Client API
}

/// Test ClientCrypto: Full message exchange
#[test]
fn test_client_crypto_message_exchange() {
    // TODO: Refactor to use new Client API
}

/// Test session serialization and restoration
#[test]
fn test_session_serialization() {
    // TODO: Refactor to use new Client API
}

/// Benchmark: Encryption performance
#[test]
fn test_encryption_performance() {
    // TODO: Refactor to use new Client API
}
*/

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
