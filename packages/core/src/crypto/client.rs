use crate::crypto::double_ratchet::{DoubleRatchetSession, EncryptedRatchetMessage, SerializableSession};
use crate::utils;
use crate::crypto::x3dh::{PublicKeyBundle, RegistrationBundle, X3DH};
use crate::crypto::CryptoProvider;
use std::marker::PhantomData;

#[cfg(feature = "post-quantum")]
use pqcrypto_kyber::{keypair as kyber_keypair, encapsulate};
#[cfg(feature = "post-quantum")]
use pqcrypto_dilithium::{keypair as dilithium_keypair, sign};
#[cfg(feature = "post-quantum")]
use crate::crypto::pq_x3dh::PQX3DHBundle;


pub struct ClientCrypto<P: CryptoProvider> {
    identity_key: P::KemPrivateKey,
    signed_prekey: P::KemPrivateKey,
    signing_key: P::SignaturePrivateKey,
    sessions: std::collections::HashMap<String, DoubleRatchetSession<P>>,

    #[cfg(feature = "post-quantum")]
    kyber_secret: pqcrypto_kyber::SecretKey,
    #[cfg(feature = "post-quantum")]
    kyber_prekey_secret: pqcrypto_kyber::SecretKey,
    #[cfg(feature = "post-quantum")]
    dilithium_secret: pqcrypto_dilithium::SecretKey,
    
    _phantom: PhantomData<P>,
}

impl<P: CryptoProvider> Default for ClientCrypto<P> {
    fn default() -> Self {
        Self::new().unwrap()
    }
}

impl<P: CryptoProvider> ClientCrypto<P> {
    pub fn new() -> Result<Self, String> {
        let (identity_key, _) = P::generate_kem_keys().map_err(|e| e.to_string())?;
        let (signed_prekey, _) = P::generate_kem_keys().map_err(|e| e.to_string())?;
        let (signing_key, _) = P::generate_signature_keys().map_err(|e| e.to_string())?;

        Ok(Self {
            identity_key,
            signed_prekey,
            signing_key,
            sessions: std::collections::HashMap::new(),
            _phantom: PhantomData,
        })
    }

    /// Регистрация - возвращаем публичные ключи клиента
    pub fn get_registration_bundle(&self) -> RegistrationBundle {
        let identity_public = P::from_private_key_to_public_key(&self.identity_key).unwrap();
        let signed_prekey_public = P::from_private_key_to_public_key(&self.signed_prekey).unwrap();

        // ✅ FIX: Derive verifying key from the actual signing_key we're using
        let verifying_key = P::from_signature_private_to_public(&self.signing_key).unwrap();

        // Подписываем signed prekey
        let signature = P::sign(&self.signing_key, signed_prekey_public.as_ref()).unwrap();

        RegistrationBundle {
            identity_public: identity_public.as_ref().to_vec(),
            signed_prekey_public: signed_prekey_public.as_ref().to_vec(),
            signature,
            verifying_key: verifying_key.as_ref().to_vec(),
            suite_id: P::suite_id(),
        }
    }

    /// Инициализация сессии - используем X3DH + Double Ratchet
    pub fn init_session(
        &mut self,
        contact_id: &str,
        remote_bundle: &PublicKeyBundle,
    ) -> Result<String, String> {
        use tracing::{debug, trace};

        debug!(target: "crypto::client", contact_id = %contact_id, "Initializing session");
        trace!(suite_id = %remote_bundle.suite_id);

        // Convert Vec<u8> from bundle to generic types
        let remote_identity_public = Self::bytes_to_kem_public_key(&remote_bundle.identity_public)?;
        let remote_signed_prekey_public = Self::bytes_to_kem_public_key(&remote_bundle.signed_prekey_public)?;
        let remote_verifying_key = Self::bytes_to_signature_public_key(&remote_bundle.verifying_key)?;

        // ✅ Generate ephemeral key pair for this session (forward secrecy!)
        debug!(target: "crypto::client", "Generating ephemeral key for X3DH");
        let (ephemeral_private, _ephemeral_public) = P::generate_kem_keys()
            .map_err(|e| format!("Failed to generate ephemeral key: {}", e))?;

        // 1. Full X3DH handshake with ephemeral key
        debug!(target: "crypto::client", "Starting X3DH handshake");
        let root_key = X3DH::<P>::perform_x3dh(
            &self.identity_key,
            &ephemeral_private,  // ✅ Use ephemeral key (not signed_prekey!)
            &remote_identity_public,
            &remote_signed_prekey_public,
            &remote_bundle.signature,
            &remote_verifying_key,
            remote_bundle.suite_id,
        )?;
        debug!(target: "crypto::client", "X3DH handshake completed successfully");

        // 2. Создание Double Ratchet сессии
        // ✅ ВАЖНО: Передаём ephemeral_private как первый DH ratchet key!
        // Bob извлечёт ephemeral_public из первого сообщения для X3DH
        debug!(target: "crypto::client", "Creating Double Ratchet session");
        let session = DoubleRatchetSession::<P>::new_x3dh_session(
            remote_bundle.suite_id,
            &root_key,
            &ephemeral_private,  // ✅ X3DH ephemeral key становится первым DH ratchet key
            &remote_identity_public,
            contact_id.to_string(),
        )?;
        debug!(target: "crypto::client", "Double Ratchet session created");

        let session_id = utils::uuid::generate_v4();
        debug!(target: "crypto::client", session_id = %session_id, "Session ID generated");

        self.sessions.insert(session_id.clone(), session);
        debug!(target: "crypto::client", "Session stored successfully");

        Ok(session_id)
    }

    #[cfg(feature = "post-quantum")]
    pub fn new_with_pqc() -> Result<Self, String> {
        // TODO: Complete PQ implementation in future
        // For now, this is a placeholder that will be implemented
        // according to the ROADMAP.md (Q2 2026: Post-Quantum Cryptography)
        unimplemented!("Post-quantum implementation not yet complete - see ROADMAP.md Фаза 2")
    }
    
    #[cfg(feature = "post-quantum")]
    pub fn perform_pq_x3dh(&self, _remote_bundle: &PQX3DHBundle) -> Result<[u8; 64], String> {
        // TODO: Complete PQ-X3DH implementation in future
        //
        // Full implementation will include:
        // 1. Classical X3DH with ephemeral keys (DH1, DH2, DH3)
        // 2. Kyber768 KEM for PQ key exchange
        // 3. Hybrid key combination: KDF(classical_secret || pq_secret)
        //
        // See ROADMAP.md Фаза 2 (Q2 2026) for details
        unimplemented!("PQ-X3DH implementation not yet complete - see ROADMAP.md Фаза 2")
    }

    pub fn init_double_ratchet_session(&mut self, contact_id: &str, remote_bundle: &PublicKeyBundle) -> Result<String, String> {
        self.init_session(contact_id, remote_bundle)
    }

    /// Создать сессию получателя при получении первого сообщения
    pub fn init_receiving_session(
        &mut self,
        contact_id: &str,
        remote_bundle: &PublicKeyBundle,
        first_message: &EncryptedRatchetMessage,
    ) -> Result<String, String> {
        use tracing::debug;

        debug!(target: "crypto::client", contact_id = %contact_id, "Initializing receiving session");

        // Convert Vec<u8> from bundle to generic types
        let remote_identity_public = Self::bytes_to_kem_public_key(&remote_bundle.identity_public)?;
        let remote_signed_prekey_public = Self::bytes_to_kem_public_key(&remote_bundle.signed_prekey_public)?;
        let remote_verifying_key = Self::bytes_to_signature_public_key(&remote_bundle.verifying_key)?;

        // ✅ Extract Alice's ephemeral public key from first message
        // In X3DH: Alice generates ephemeral key and includes it in first message (dh_public_key)
        let alice_ephemeral_public = Self::bytes_to_kem_public_key(&first_message.dh_public_key)?;
        debug!(target: "crypto::client", "Extracted Alice's ephemeral key from first message");

        // 1. Verify Alice's signed prekey signature
        debug!(target: "crypto::client", "Verifying Alice's signed prekey signature");
        P::verify(
            &remote_verifying_key,
            remote_signed_prekey_public.as_ref(),
            &remote_bundle.signature,
        ).map_err(|e| format!("Signature verification failed: {}", e))?;

        // 2. X3DH as receiver - use Alice's ephemeral PUBLIC key
        debug!(target: "crypto::client", "Starting X3DH handshake as receiver");
        let root_key = X3DH::<P>::perform_x3dh_receiver(
            &self.identity_key,                 // Bob's identity private
            &self.signed_prekey,                // Bob's signed prekey private
            &remote_identity_public,            // Alice's identity public
            &alice_ephemeral_public,            // Alice's ephemeral public (from first msg)
        )?;

        // 2. Создание Double Ratchet сессии для получателя
        let session = DoubleRatchetSession::<P>::new_receiving_session(
            remote_bundle.suite_id,
            &root_key,
            &self.identity_key,
            first_message,
            contact_id.to_string(),
        )?;

        let session_id = utils::uuid::generate_v4();
        self.sessions.insert(session_id.clone(), session);

        Ok(session_id)
    }

    pub fn encrypt_ratchet_message(&mut self, session_id: &str, plaintext: &[u8]) -> Result<EncryptedRatchetMessage, String> {
        let session = self.sessions
            .get_mut(session_id)
            .ok_or_else(|| format!("Session not found: {}", session_id))?;

        session.encrypt(plaintext)
    }

    pub fn decrypt_ratchet_message(&mut self, session_id: &str, encrypted: &EncryptedRatchetMessage) -> Result<Vec<u8>, String> {
        use tracing::{debug, trace};

        debug!(
            target: "crypto::client",
            session_id = %session_id,
            msg_num = %encrypted.message_number,
            "Decrypting ratchet message"
        );
        trace!(
            dh_pk_len = %encrypted.dh_public_key.len(),
            ciphertext_len = %encrypted.ciphertext.len(),
            nonce_len = %encrypted.nonce.len(),
        );

        let session = self.sessions
            .get_mut(session_id)
            .ok_or_else(|| {
                debug!(target: "crypto::client", session_id = %session_id, "Session not found");
                format!("Session not found: {}", session_id)
            })?;

        debug!(target: "crypto::client", "Session found, calling decrypt");
        let result = session.decrypt(encrypted);

        if result.is_ok() {
            debug!(target: "crypto::client", "Decryption successful");
        } else {
            debug!(target: "crypto::client", error = ?result, "Decryption failed");
        }

        result
    }

    pub fn export_session(&self, session_id: &str) -> Result<Vec<u8>, String> {
        let session = self.sessions
            .get(session_id)
            .ok_or_else(|| format!("Session not found: {}", session_id))?;

        let serializable = session.to_serializable();
        utils::serialization::to_bytes(&serializable)
    }

    pub fn restore_session(&mut self, session_data: &[u8]) -> Result<String, String> {
        let serializable: SerializableSession = utils::serialization::from_bytes(session_data)?;
        let session = DoubleRatchetSession::<P>::from_serializable(serializable)?;
        let session_id = utils::uuid::generate_v4();

        self.sessions.insert(session_id.clone(), session);

        Ok(session_id)
    }

    // Helper methods to convert bytes to generic key types
    // ✅ SAFE: No unsafe code, uses CryptoProvider trait methods
    fn bytes_to_kem_public_key(bytes: &[u8]) -> Result<P::KemPublicKey, String> {
        Ok(P::kem_public_key_from_bytes(bytes.to_vec()))
    }

    // ✅ SAFE: No unsafe code, uses CryptoProvider trait methods
    fn bytes_to_signature_public_key(bytes: &[u8]) -> Result<P::SignaturePublicKey, String> {
        Ok(P::signature_public_key_from_bytes(bytes.to_vec()))
    }
}