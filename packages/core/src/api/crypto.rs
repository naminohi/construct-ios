use crate::crypto::keys::KeyManager;
use crate::crypto::session::SessionManager;
use crate::crypto::x3dh::PublicKeyBundle;
use crate::crypto::{ClientCrypto, CryptoProvider};
use crate::utils::error::{ConstructError, Result};
use serde::{Deserialize, Serialize};
use std::marker::PhantomData;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct KeyBundle {
    pub identity_public: Vec<u8>,
    pub signed_prekey_public: Vec<u8>,
    pub signature: Vec<u8>,
    pub verifying_key: Vec<u8>,
    pub suite_id: u16, // Added
}

impl From<PublicKeyBundle> for KeyBundle {
    fn from(bundle: PublicKeyBundle) -> Self {
        Self {
            identity_public: bundle.identity_public,
            signed_prekey_public: bundle.signed_prekey_public,
            signature: bundle.signature,
            verifying_key: bundle.verifying_key,
            suite_id: bundle.suite_id, // Added
        }
    }
}

impl From<crate::crypto::RegistrationBundle> for KeyBundle {
    fn from(bundle: crate::crypto::RegistrationBundle) -> Self {
        Self {
            identity_public: bundle.identity_public,
            signed_prekey_public: bundle.signed_prekey_public,
            signature: bundle.signature,
            verifying_key: bundle.verifying_key,
            suite_id: bundle.suite_id, // Added
        }
    }
}

impl From<KeyBundle> for PublicKeyBundle {
    fn from(bundle: KeyBundle) -> Self {
        Self {
            identity_public: bundle.identity_public,
            signed_prekey_public: bundle.signed_prekey_public,
            signature: bundle.signature,
            verifying_key: bundle.verifying_key,
            suite_id: bundle.suite_id, // Added
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RegistrationBundleB64 {
    pub identity_public: String,
    pub signed_prekey_public: String,
    pub signature: String,
    pub verifying_key: String,
    pub suite_id: String, // Added
}

pub struct CryptoCore<P: CryptoProvider> {
    key_manager: KeyManager<P>,
    session_manager: SessionManager<P>,
    client: ClientCrypto<P>,
    _phantom: PhantomData<P>,
}

impl<P: CryptoProvider> CryptoCore<P> {
    pub fn new() -> Result<Self> {
        let mut key_manager = KeyManager::<P>::new();
        key_manager.initialize()?;

        let client = ClientCrypto::<P>::new().map_err(ConstructError::CryptoError)?;

        Ok(Self {
            key_manager,
            session_manager: SessionManager::<P>::new(),
            client,
            _phantom: PhantomData,
        })
    }

    pub fn key_manager(&self) -> &KeyManager<P> {
        &self.key_manager
    }

    pub fn key_manager_mut(&mut self) -> &mut KeyManager<P> {
        &mut self.key_manager
    }

    pub fn session_manager(&self) -> &SessionManager<P> {
        &self.session_manager
    }

    pub fn session_manager_mut(&mut self) -> &mut SessionManager<P> {
        &mut self.session_manager
    }

    pub fn export_registration_bundle(&self) -> Result<KeyBundle> {
        let bundle = self.key_manager.export_registration_bundle()?;
        Ok(bundle.into())
    }

    pub fn export_registration_bundle_b64(&self) -> Result<RegistrationBundleB64> {
        use base64::Engine;
        let bundle = self.key_manager.export_registration_bundle()?;
        Ok(RegistrationBundleB64 {
            identity_public: base64::engine::general_purpose::STANDARD.encode(&bundle.identity_public),
            signed_prekey_public: base64::engine::general_purpose::STANDARD.encode(&bundle.signed_prekey_public),
            signature: base64::engine::general_purpose::STANDARD.encode(&bundle.signature),
            verifying_key: base64::engine::general_purpose::STANDARD.encode(&bundle.verifying_key),
            suite_id: bundle.suite_id.to_string(),
        })
    }

    pub fn export_public_bundle(&self) -> Result<KeyBundle> {
        let bundle = self.key_manager.export_public_bundle()?;
        Ok(bundle.into())
    }

    pub fn rotate_prekey(&mut self) -> Result<()> {
        self.key_manager.rotate_signed_prekey()
    }

    pub fn sign_data(&self, data: &[u8]) -> Result<Vec<u8>> {
        self.key_manager.sign(data)
    }

    pub fn has_session(&self, contact_id: &str) -> bool {
        self.session_manager.has_session(contact_id)
    }

    pub fn active_sessions_count(&self) -> usize {
        self.session_manager.session_count()
    }

    pub fn cleanup_old_sessions(&mut self, max_age_seconds: i64) {
        self.session_manager
            .cleanup_sessions_older_than(max_age_seconds);
    }

    pub fn init_session(&mut self, contact_id: &str, remote_bundle: &KeyBundle) -> Result<String> {
        eprintln!("[CryptoCore] init_session called for contact: {}", contact_id);
        eprintln!("[CryptoCore] Converting KeyBundle to PublicKeyBundle...");
        let public_bundle: PublicKeyBundle = remote_bundle.clone().into();
        eprintln!("[CryptoCore] PublicKeyBundle created, calling client.init_session...");
        let result = self.client
            .init_session(contact_id, &public_bundle)
            .map_err(ConstructError::CryptoError);
        eprintln!("[CryptoCore] client.init_session returned: {:?}", result.is_ok());
        result
    }

    pub fn init_receiving_session(
        &mut self,
        contact_id: &str,
        remote_bundle: &KeyBundle,
        first_message: &crate::crypto::double_ratchet::EncryptedRatchetMessage,
    ) -> Result<String> {
        eprintln!("[CryptoCore] init_receiving_session called for contact: {}", contact_id);
        let public_bundle: PublicKeyBundle = remote_bundle.clone().into();
        self.client
            .init_receiving_session(contact_id, &public_bundle, first_message)
            .map_err(ConstructError::CryptoError)
    }

    pub fn encrypt_message(
        &mut self,
        session_id: &str,
        plaintext: &str,
    ) -> Result<crate::crypto::double_ratchet::EncryptedRatchetMessage> {
        self.client
            .encrypt_ratchet_message(session_id, plaintext.as_bytes())
            .map_err(ConstructError::CryptoError)
    }

    pub fn decrypt_message(
        &mut self,
        session_id: &str,
        message: &crate::crypto::double_ratchet::EncryptedRatchetMessage,
    ) -> Result<String> {
        let plaintext = self
            .client
            .decrypt_ratchet_message(session_id, message)
            .map_err(ConstructError::CryptoError)?;

        String::from_utf8(plaintext)
            .map_err(|e| ConstructError::SerializationError(format!("Invalid UTF-8: {}", e)))
    }

    pub fn client(&self) -> &ClientCrypto<P> {
        &self.client
    }

    pub fn client_mut(&mut self) -> &mut ClientCrypto<P> {
        &mut self.client
    }

    // DEPRECATED: These methods don't work with generic CryptoProvider
    // They should be refactored to work with Vec<u8> instead of concrete types
    // pub fn export_private_keys(&self) -> Result<crate::crypto::master_key::PrivateKeys> {
    //     let identity_secret = self.key_manager.identity_secret_key()?;
    //     let identity_bytes = identity_secret.as_ref().to_vec();
    //
    //     let signing_key = self.key_manager.signing_secret_key()?;
    //     let signing_bytes = signing_key.as_ref().to_vec();
    //
    //     let prekey = self.key_manager.current_signed_prekey()?;
    //     let prekey_bytes = prekey.key_pair.0.as_ref().to_vec();
    //
    //     Ok(crate::crypto::master_key::PrivateKeys::new(
    //         identity_bytes,
    //         signing_bytes,
    //         prekey_bytes,
    //     ))
    // }
    //
    // pub fn import_private_keys(
    //     &mut self,
    //     keys: &crate::crypto::master_key::PrivateKeys,
    //     prekey_signature: Vec<u8>,
    // ) -> Result<()> {
    //     // This method requires a generic way to construct keys from bytes
    //     // which is not currently supported in CryptoProvider trait
    //     unimplemented!("import_private_keys not compatible with generic CryptoProvider")
    // }
}

impl<P: CryptoProvider> Default for CryptoCore<P> {
    fn default() -> Self {
        Self::new().expect("Failed to create CryptoCore")
    }
}

pub fn create_client<P: CryptoProvider>() -> Result<ClientCrypto<P>> {
    ClientCrypto::<P>::new().map_err(ConstructError::CryptoError)
}

pub fn get_registration_bundle<P: CryptoProvider>(client: &ClientCrypto<P>) -> Result<KeyBundle> {
    let bundle = client.get_registration_bundle();
    Ok(KeyBundle {
        identity_public: bundle.identity_public,
        signed_prekey_public: bundle.signed_prekey_public,
        signature: bundle.signature,
        verifying_key: bundle.verifying_key,
        suite_id: bundle.suite_id,
    })
}

pub fn serialize_key_bundle(bundle: &KeyBundle) -> Result<String> {
    serde_json::to_string(bundle).map_err(|e| ConstructError::SerializationError(e.to_string()))
}

pub fn deserialize_key_bundle(json: &str) -> Result<KeyBundle> {
    serde_json::from_str(json).map_err(|e| ConstructError::SerializationError(e.to_string()))
}

pub fn bytes_to_base64(bytes: &[u8]) -> String {
    use base64::Engine;
    base64::engine::general_purpose::STANDARD.encode(bytes)
}

pub fn base64_to_bytes(base64_str: &str) -> Result<Vec<u8>> {
    use base64::Engine;
    base64::engine::general_purpose::STANDARD
        .decode(base64_str)
        .map_err(|e| ConstructError::SerializationError(format!("Invalid base64: {}", e)))
}

pub fn generate_random_bytes(len: usize) -> Vec<u8> {
    use rand::RngCore;
    let mut bytes = vec![0u8; len];
    rand::rngs::OsRng.fill_bytes(&mut bytes);
    bytes
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::crypto::classic_suite::ClassicSuiteProvider;

    #[test]
    fn test_crypto_manager_creation() {
        let manager = CryptoCore::<ClassicSuiteProvider>::new();
        assert!(manager.is_ok());

        let manager = manager.unwrap();
        assert_eq!(manager.active_sessions_count(), 0);
    }

    #[test]
    fn test_base64_conversion() {
        let data = b"hello world";
        let b64 = bytes_to_base64(data);
        let decoded = base64_to_bytes(&b64).unwrap();
        assert_eq!(data, decoded.as_slice());
    }

    #[test]
    fn test_random_bytes() {
        let bytes1 = generate_random_bytes(32);
        let bytes2 = generate_random_bytes(32);

        assert_eq!(bytes1.len(), 32);
        assert_eq!(bytes2.len(), 32);
        assert_ne!(bytes1, bytes2); // Должны быть разными
    }

    #[test]
    fn test_export_registration_bundle() {
        let manager = CryptoCore::<ClassicSuiteProvider>::new().unwrap();
        let bundle = manager.export_registration_bundle();
        assert!(bundle.is_ok());

        let bundle = bundle.unwrap();
        assert_eq!(bundle.identity_public.len(), 32);
        assert_eq!(bundle.signed_prekey_public.len(), 32);
        assert_eq!(bundle.signature.len(), 64);
        assert_eq!(bundle.verifying_key.len(), 32);
    }
}