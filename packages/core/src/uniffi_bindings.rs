use crate::api::crypto::CryptoCore;
use crate::crypto::classic_suite::ClassicSuiteProvider;
use rmp_serde::{from_slice, to_vec_named};
use serde::{Deserialize, Serialize};
use std::sync::{Arc, Mutex};

// Wrapper for CryptoCore to make it work with UniFFI
// Note: We use UDL definition, not derive macro
// UniFFI wraps this in Arc automatically, so we only need Mutex here
pub struct ClassicCryptoCore {
    inner: Mutex<CryptoCore<ClassicSuiteProvider>>,
}

// Error type that matches UDL definition (flat errors)
// Note: We use UDL definition, not derive macro
#[derive(Debug, thiserror::Error)]
pub enum CryptoError {
    #[error("Initialization failed")]
    InitializationFailed,

    #[error("Session not found")]
    SessionNotFound,

    #[error("Session initialization failed")]
    SessionInitializationFailed,

    #[error("Encryption failed")]
    EncryptionFailed,

    #[error("Decryption failed")]
    DecryptionFailed,

    #[error("Invalid key data")]
    InvalidKeyData,

    #[error("Invalid ciphertext")]
    InvalidCiphertext,

    #[error("Serialization failed")]
    SerializationFailed,
}

// Convert our internal errors to UniFFI CryptoError
impl From<crate::utils::error::ConstructError> for CryptoError {
    fn from(_err: crate::utils::error::ConstructError) -> Self {
        CryptoError::InitializationFailed
    }
}

// Registration bundle as JSON - matches UDL
// Note: We use UDL definition, not derive macro
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RegistrationBundleJson {
    pub identity_public: String,
    pub signed_prekey_public: String,
    pub signature: String,
    pub verifying_key: String,
    pub suite_id: String,
}

// Key bundle for session initialization
#[derive(Debug, Clone, Serialize, Deserialize)]
struct KeyBundle {
    identity_public: Vec<u8>,
    signed_prekey_public: Vec<u8>,
    signature: Vec<u8>,
    verifying_key: Vec<u8>,
    suite_id: u16,
}

// UniFFI interface implementation (exported via UDL, not proc-macros)
impl ClassicCryptoCore {
    /// Export registration bundle as JSON string
    pub fn export_registration_bundle_json(&self) -> Result<String, CryptoError> {
        let core = self.inner.lock().unwrap();
        let bundle = core.export_registration_bundle_b64()
            .map_err(|_| CryptoError::InitializationFailed)?;

        let json_bundle = RegistrationBundleJson {
            identity_public: bundle.identity_public,
            signed_prekey_public: bundle.signed_prekey_public,
            signature: bundle.signature,
            verifying_key: bundle.verifying_key,
            suite_id: bundle.suite_id.to_string(),
        };

        serde_json::to_string(&json_bundle)
            .map_err(|_| CryptoError::SerializationFailed)
    }

    /// Initialize a session with a contact
    pub fn init_session(
        &self,
        contact_id: String,
        recipient_bundle: Vec<u8>,
    ) -> Result<String, CryptoError> {
        eprintln!("[UniFFI] init_session called for contact: {}", contact_id);
        eprintln!("[UniFFI] recipient_bundle length: {} bytes", recipient_bundle.len());

        let bundle_str = std::str::from_utf8(&recipient_bundle)
            .map_err(|e| {
                eprintln!("[UniFFI] Failed to parse UTF-8: {}", e);
                CryptoError::InvalidKeyData
            })?;

        eprintln!("[UniFFI] Bundle string: {}", bundle_str);

        let key_bundle: KeyBundle = serde_json::from_str(bundle_str)
            .map_err(|e| {
                eprintln!("[UniFFI] Failed to parse JSON: {}", e);
                CryptoError::InvalidKeyData
            })?;

        eprintln!("[UniFFI] KeyBundle parsed successfully");

        // Convert to the internal KeyBundle type
        let internal_bundle = crate::api::crypto::KeyBundle {
            identity_public: key_bundle.identity_public.clone(),
            signed_prekey_public: key_bundle.signed_prekey_public.clone(),
            signature: key_bundle.signature.clone(),
            verifying_key: key_bundle.verifying_key.clone(),
            suite_id: key_bundle.suite_id,
        };

        eprintln!("[UniFFI] Internal bundle created, acquiring lock...");
        let mut core = self.inner.lock().unwrap();
        eprintln!("[UniFFI] Lock acquired, calling core.init_session...");

        let result = core.init_session(&contact_id, &internal_bundle)
            .map_err(|e| {
                eprintln!("[UniFFI] core.init_session failed: {:?}", e);
                CryptoError::SessionInitializationFailed
            });

        eprintln!("[UniFFI] init_session result: {:?}", result.is_ok());
        result
    }

    /// Encrypt a message for a session
    pub fn encrypt_message(
        &self,
        session_id: String,
        plaintext: String,
    ) -> Result<Vec<u8>, CryptoError> {
        let mut core = self.inner.lock().unwrap();
        let encrypted_message = core
            .encrypt_message(&session_id, &plaintext)
            .map_err(|_| CryptoError::EncryptionFailed)?;

        to_vec_named(&encrypted_message)
            .map_err(|_| CryptoError::SerializationFailed)
    }

    /// Decrypt a message from a session
    pub fn decrypt_message(
        &self,
        session_id: String,
        ciphertext: Vec<u8>,
    ) -> Result<String, CryptoError> {
        let encrypted_message = from_slice(&ciphertext)
            .map_err(|_| CryptoError::InvalidCiphertext)?;

        let mut core = self.inner.lock().unwrap();
        core.decrypt_message(&session_id, &encrypted_message)
            .map_err(|_| CryptoError::DecryptionFailed)
    }
}

/// Create a new CryptoCore instance (exported via UDL)
/// UniFFI automatically wraps this in Arc<>, so we return Arc<ClassicCryptoCore>
pub fn create_crypto_core() -> Result<Arc<ClassicCryptoCore>, CryptoError> {
    let core = CryptoCore::<ClassicSuiteProvider>::new()
        .map_err(|_| CryptoError::InitializationFailed)?;

    Ok(Arc::new(ClassicCryptoCore {
        inner: Mutex::new(core),
    }))
}
