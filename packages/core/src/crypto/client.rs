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

        // Generate signature public key from signature private key
        let (_, verifying_key_generated) = P::generate_signature_keys().unwrap();

        // Подписываем signed prekey
        let signature = P::sign(&self.signing_key, signed_prekey_public.as_ref()).unwrap();

        RegistrationBundle {
            identity_public: identity_public.as_ref().to_vec(),
            signed_prekey_public: signed_prekey_public.as_ref().to_vec(),
            signature,
            verifying_key: verifying_key_generated.as_ref().to_vec(),
            suite_id: P::suite_id(),
        }
    }

    /// Инициализация сессии - используем X3DH + Double Ratchet
    pub fn init_session(
        &mut self,
        contact_id: &str,
        remote_bundle: &PublicKeyBundle,
    ) -> Result<String, String> {
        eprintln!("[ClientCrypto] init_session called for contact: {}", contact_id);
        eprintln!("[ClientCrypto] suite_id: {}", remote_bundle.suite_id);

        // Convert Vec<u8> from bundle to generic types
        eprintln!("[ClientCrypto] Converting bytes to keys...");
        let remote_identity_public = Self::bytes_to_kem_public_key(&remote_bundle.identity_public)?;
        eprintln!("[ClientCrypto] remote_identity_public converted");
        let remote_signed_prekey_public = Self::bytes_to_kem_public_key(&remote_bundle.signed_prekey_public)?;
        eprintln!("[ClientCrypto] remote_signed_prekey_public converted");
        let remote_verifying_key = Self::bytes_to_signature_public_key(&remote_bundle.verifying_key)?;
        eprintln!("[ClientCrypto] remote_verifying_key converted");

        // 1. X3DH handshake
        eprintln!("[ClientCrypto] Starting X3DH handshake...");
        let root_key = X3DH::<P>::perform_x3dh(
            &self.identity_key,
            &self.signed_prekey,
            &remote_identity_public,
            &remote_signed_prekey_public,
            &remote_bundle.signature,
            &remote_verifying_key,
            remote_bundle.suite_id,
        )?;
        eprintln!("[ClientCrypto] X3DH handshake completed successfully");

        // 2. Создание Double Ratchet сессии
        eprintln!("[ClientCrypto] Creating Double Ratchet session...");
        let session = DoubleRatchetSession::<P>::new_x3dh_session(
            remote_bundle.suite_id,
            &root_key,
            &remote_identity_public,
            &self.identity_key,
            contact_id.to_string(),
        )?;
        eprintln!("[ClientCrypto] Double Ratchet session created successfully");

        eprintln!("[ClientCrypto] Generating session ID...");
        let session_id = utils::uuid::generate_v4();
        eprintln!("[ClientCrypto] Session ID: {}", session_id);

        eprintln!("[ClientCrypto] Storing session...");
        self.sessions.insert(session_id.clone(), session);
        eprintln!("[ClientCrypto] Session stored successfully");

        Ok(session_id)
    }

    #[cfg(feature = "post-quantum")]
    pub fn new_with_pqc() -> Result<Self, String> {
        // Классические ключи
        let identity_key = x25519_dalek::StaticSecret::random_from_rng(rand::rngs::OsRng);
        let signed_prekey = x25519_dalek::StaticSecret::random_from_rng(rand::rngs::OsRng);
        let signing_key = ed25519_dalek::SigningKey::generate(&mut rand::rngs::OsRng);
        
        // Пост-квантовые ключи
        let (_, kyber_sk) = kyber_keypair().map_err(|e| e.to_string())?;
        let (_, kyber_prekey_sk) = kyber_keypair().map_err(|e| e.to_string())?;
        let (_, dilithium_sk) = dilithium_keypair().map_err(|e| e.to_string())?;
        
        Ok(Self {
            identity_key,
            signed_prekey,
            signing_key,
            sessions: std::collections::HashMap::new(),
            storage: None,
            kyber_secret: kyber_sk,
            kyber_prekey_secret: kyber_prekey_sk,
            dilithium_secret: dilithium_sk,
            _phantom: PhantomData,
        })
    }
    
    #[cfg(feature = "post-quantum")]
    pub fn perform_pq_x3dh(&self, remote_bundle: &PQX3DHBundle) -> Result<[u8; 64], String> {
        // This is a placeholder as per the markdown, and needs more implementation details
        
        // 1. Классический X3DH (needs to be implemented correctly)
        // let classical_secret = X3DH::perform_x3dh(...)
        unimplemented!("Classical part of PQX3DH is not implemented yet");

        // 2. Пост-квантовый обмен (needs proper key conversion and error handling)
        // let public_key = pqcrypto_kyber::PublicKey::from_bytes(&remote_bundle.kyber_public_key)?;
        // let (kyber_ciphertext, kyber_shared) = encapsulate(&public_key)?;
        // ... and for the prekey ...
        unimplemented!("Post-quantum part of PQX3DH is not implemented yet");
        
        // 3. Комбинируем через HKDF
        // let combined = ...;
        // let final_key = ...;
        // Ok(final_key)
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
        // Convert Vec<u8> from bundle to generic types
        let remote_identity_public = Self::bytes_to_kem_public_key(&remote_bundle.identity_public)?;
        let remote_signed_prekey_public = Self::bytes_to_kem_public_key(&remote_bundle.signed_prekey_public)?;
        let remote_verifying_key = Self::bytes_to_signature_public_key(&remote_bundle.verifying_key)?;

        // 1. X3DH handshake
        let root_key = X3DH::<P>::perform_x3dh(
            &self.identity_key,
            &self.signed_prekey,
            &remote_identity_public,
            &remote_signed_prekey_public,
            &remote_bundle.signature,
            &remote_verifying_key,
            remote_bundle.suite_id,
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
        let session = self.sessions
            .get_mut(session_id)
            .ok_or_else(|| format!("Session not found: {}", session_id))?;

        session.decrypt(encrypted)
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
        eprintln!("[ClientCrypto] bytes_to_kem_public_key called, input length: {}", bytes.len());
        eprintln!("[ClientCrypto] Input bytes (first 10): {:?}", &bytes[..10.min(bytes.len())]);

        let key_vec = bytes.to_vec();
        let result = P::kem_public_key_from_bytes(key_vec);

        eprintln!("[ClientCrypto] Result length: {}", result.as_ref().len());
        eprintln!("[ClientCrypto] Result bytes (first 10): {:?}", &result.as_ref()[..10.min(result.as_ref().len())]);
        Ok(result)
    }

    // ✅ SAFE: No unsafe code, uses CryptoProvider trait methods
    fn bytes_to_signature_public_key(bytes: &[u8]) -> Result<P::SignaturePublicKey, String> {
        eprintln!("[ClientCrypto] bytes_to_signature_public_key called, input length: {}", bytes.len());
        eprintln!("[ClientCrypto] Input bytes (first 10): {:?}", &bytes[..10.min(bytes.len())]);

        let key_vec = bytes.to_vec();
        let result = P::signature_public_key_from_bytes(key_vec);

        eprintln!("[ClientCrypto] Result length: {}", result.as_ref().len());
        eprintln!("[ClientCrypto] Result bytes (first 10): {:?}", &result.as_ref()[..10.min(result.as_ref().len())]);
        Ok(result)
    }
}