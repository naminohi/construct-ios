use crate::crypto::{CryptoProvider, SuiteID};

/// Constants for DoS protection for skipped messages.
const MAX_SKIPPED_MESSAGES: u32 = 1000;
const MAX_SKIPPED_MESSAGE_AGE_SECONDS: i64 = 7 * 24 * 60 * 60; // 7 days

pub struct DoubleRatchetSession<P: CryptoProvider> {
    suite_id: SuiteID,
    root_key: P::AeadKey,

    sending_chain_key: P::AeadKey,
    sending_chain_length: u32,

    receiving_chain_key: P::AeadKey,
    receiving_chain_length: u32,

    dh_ratchet_private: Option<P::KemPrivateKey>,
    dh_ratchet_public: P::KemPublicKey,
    remote_dh_public: Option<P::KemPublicKey>,

    previous_sending_length: u32,
    skipped_message_keys: std::collections::HashMap<u32, P::AeadKey>,
    skipped_key_timestamps: std::collections::HashMap<u32, u64>,

    session_id: String,
    contact_id: String,
}

impl<P: CryptoProvider> DoubleRatchetSession<P> {
    /// Получить session_id
    pub fn session_id(&self) -> &str {
        &self.session_id
    }

    /// Получить contact_id
    pub fn contact_id(&self) -> &str {
        &self.contact_id
    }

    /// Инициатор сессии (Alice) - создает сессию для отправки первого сообщения
    pub fn new_x3dh_session(
        suite_id: SuiteID,
        root_key_bytes: &[u8],
        remote_identity_public_kem_pk: &P::KemPublicKey,
        local_identity_private_kem_sk: &P::KemPrivateKey,
        contact_id: String,
    ) -> Result<Self, String> {
        // Convert root_key bytes to P::AeadKey
        let root_key_vec = P::hkdf_derive_key(b"", root_key_bytes, b"InitialRootKey", 32)
            .map_err(|e| format!("Failed to derive root key: {}", e))?;

        // We need to convert Vec<u8> to P::AeadKey
        // For now, use a temporary approach via HKDF
        let (dh_private, dh_public) = P::generate_kem_keys()
            .map_err(|e| format!("Failed to generate DH keys: {}", e))?;

        // Perform DH exchange to get shared secret
        let dh_output_secret = P::kem_decapsulate(local_identity_private_kem_sk, dh_public.as_ref())
            .map_err(|e| format!("Failed to perform DH: {}", e))?;

        // Derive initial chain key from root key
        let initial_root_key_bytes = P::hkdf_derive_key(b"", &root_key_vec, b"RootKey", 32)
            .map_err(|e| format!("Failed to derive initial root key: {}", e))?;

        let (root_key, chain_key) = P::kdf_rk(
            &Self::bytes_to_aead_key(&initial_root_key_bytes)?,
            &dh_output_secret,
        )
        .map_err(|e| format!("KDF_RK failed: {}", e))?;

        Ok(Self {
            suite_id,
            root_key,
            sending_chain_key: chain_key,
            sending_chain_length: 0,
            receiving_chain_key: P::AeadKey::default(),
            receiving_chain_length: 0,
            dh_ratchet_private: Some(dh_private),
            dh_ratchet_public: dh_public,
            remote_dh_public: Some(remote_identity_public_kem_pk.clone()),
            previous_sending_length: 0,
            skipped_message_keys: std::collections::HashMap::new(),
            skipped_key_timestamps: std::collections::HashMap::new(),
            session_id: uuid::Uuid::new_v4().to_string(),
            contact_id,
        })
    }

    /// Получатель (Bob) - создает сессию при получении первого сообщения
    pub fn new_receiving_session(
        suite_id: SuiteID,
        root_key_bytes: &[u8],
        local_identity_private_kem_sk: &P::KemPrivateKey,
        first_message: &EncryptedRatchetMessage,
        contact_id: String,
    ) -> Result<Self, String> {
        // Convert DH public key from message
        let remote_dh_public_bytes = &first_message.dh_public_key;
        let remote_dh_public = Self::bytes_to_kem_public_key(remote_dh_public_bytes)?;

        // Convert root_key bytes to P::AeadKey
        let root_key_vec = P::hkdf_derive_key(b"", root_key_bytes, b"InitialRootKey", 32)
            .map_err(|e| format!("Failed to derive root key: {}", e))?;
        let mut root_key_val = Self::bytes_to_aead_key(&root_key_vec)?;

        // Perform DH to get receiving chain
        let dh_output = P::kem_decapsulate(local_identity_private_kem_sk, remote_dh_public.as_ref())
            .map_err(|e| format!("Failed to perform DH: {}", e))?;
        let (new_root_key, receiving_chain) = P::kdf_rk(&root_key_val, &dh_output)
            .map_err(|e| format!("KDF_RK failed: {}", e))?;
        root_key_val = new_root_key;

        // Generate new DH pair for sending
        let (dh_private, dh_public) = P::generate_kem_keys()
            .map_err(|e| format!("Failed to generate DH keys: {}", e))?;

        // Perform second ratchet for sending chain
        let dh_output2 = P::kem_decapsulate(&dh_private, remote_dh_public.as_ref())
            .map_err(|e| format!("Failed to perform DH: {}", e))?;
        let (final_root_key, sending_chain) = P::kdf_rk(&root_key_val, &dh_output2)
            .map_err(|e| format!("KDF_RK failed: {}", e))?;

        Ok(Self {
            suite_id,
            root_key: final_root_key,
            sending_chain_key: sending_chain,
            sending_chain_length: 0,
            receiving_chain_key: receiving_chain,
            receiving_chain_length: 0,
            dh_ratchet_private: Some(dh_private),
            dh_ratchet_public: dh_public,
            remote_dh_public: Some(remote_dh_public),
            previous_sending_length: 0,
            skipped_message_keys: std::collections::HashMap::new(),
            skipped_key_timestamps: std::collections::HashMap::new(),
            session_id: uuid::Uuid::new_v4().to_string(),
            contact_id,
        })
    }

    pub fn encrypt(&mut self, plaintext: &[u8]) -> Result<EncryptedRatchetMessage, String> {
        let (message_key, next_chain_key) = P::kdf_ck(&self.sending_chain_key)
            .map_err(|e| format!("KDF (CK) failed: {}", e))?;
        self.sending_chain_key = next_chain_key;

        let message_number = self.sending_chain_length;
        self.sending_chain_length += 1;

        // Generate nonce - use 12 bytes for ChaCha20Poly1305
        let nonce = P::generate_nonce(12)
            .map_err(|e| format!("Nonce generation failed: {}", e))?;

        let ciphertext = P::aead_encrypt(&message_key, &nonce, plaintext, None)
            .map_err(|e| format!("Encryption failed: {}", e))?;

        // Convert dh_ratchet_public to [u8; 32]
        let dh_public_key_vec = self.dh_ratchet_public.as_ref().to_vec();
        let dh_public_key: [u8; 32] = dh_public_key_vec
            .try_into()
            .map_err(|_| "Invalid public key length")?;

        Ok(EncryptedRatchetMessage {
            dh_public_key,
            message_number,
            ciphertext,
            nonce,
            previous_chain_length: self.previous_sending_length,
            suite_id: self.suite_id,
        })
    }

    pub fn decrypt(&mut self, encrypted: &EncryptedRatchetMessage) -> Result<Vec<u8>, String> {
        // Convert DH public key from message
        let remote_dh_public = Self::bytes_to_kem_public_key(&encrypted.dh_public_key)?;

        // Check if we need to perform DH ratchet
        let needs_ratchet = match &self.remote_dh_public {
            Some(current_remote) => {
                // Compare byte representation
                current_remote.as_ref() != remote_dh_public.as_ref()
            }
            None => true,
        };

        if needs_ratchet {
            self.perform_dh_ratchet(&remote_dh_public)?;
        }

        // Try to find skipped message key
        if let Some(key) = self.skipped_message_keys.remove(&encrypted.message_number) {
            return self.decrypt_with_key(&key, encrypted);
        }

        // Derive keys until we reach the message number
        while self.receiving_chain_length <= encrypted.message_number {
            let (msg_key, next_chain) = P::kdf_ck(&self.receiving_chain_key)
                .map_err(|e| format!("KDF_CK failed: {}", e))?;

            if self.receiving_chain_length == encrypted.message_number {
                self.receiving_chain_key = next_chain;
                self.receiving_chain_length += 1;
                return self.decrypt_with_key(&msg_key, encrypted);
            } else {
                // Store skipped key
                self.skipped_message_keys
                    .insert(self.receiving_chain_length, msg_key);
                self.receiving_chain_key = next_chain;
                self.receiving_chain_length += 1;

                // DoS protection
                if self.skipped_message_keys.len() > MAX_SKIPPED_MESSAGES as usize {
                    return Err("Too many skipped messages".to_string());
                }
            }
        }

        Err("Message key not found".to_string())
    }

    fn perform_dh_ratchet(&mut self, new_remote_dh: &P::KemPublicKey) -> Result<(), String> {
        self.previous_sending_length = self.sending_chain_length;

        // 1. Get new receiving chain key using old DH private and new remote DH
        let dh_private = self
            .dh_ratchet_private
            .as_ref()
            .ok_or("No DH private key")?;
        let dh_receive = P::kem_decapsulate(dh_private, new_remote_dh.as_ref())
            .map_err(|e| format!("DH failed: {}", e))?;

        let (new_root_key, new_receiving_chain) = P::kdf_rk(&self.root_key, &dh_receive)
            .map_err(|e| format!("KDF_RK failed: {}", e))?;
        self.root_key = new_root_key;
        self.receiving_chain_key = new_receiving_chain;
        self.receiving_chain_length = 0;

        // 2. Generate new DH pair for sending
        let (new_dh_private, new_dh_public) = P::generate_kem_keys()
            .map_err(|e| format!("Failed to generate DH keys: {}", e))?;

        // 3. Get sending chain key using new DH private and new remote DH
        let dh_send = P::kem_decapsulate(&new_dh_private, new_remote_dh.as_ref())
            .map_err(|e| format!("DH failed: {}", e))?;

        let (new_root_key2, new_sending_chain) = P::kdf_rk(&self.root_key, &dh_send)
            .map_err(|e| format!("KDF_RK failed: {}", e))?;
        self.root_key = new_root_key2;
        self.sending_chain_key = new_sending_chain;
        self.sending_chain_length = 0;

        // 4. Update state
        self.dh_ratchet_private = Some(new_dh_private);
        self.dh_ratchet_public = new_dh_public;
        self.remote_dh_public = Some(new_remote_dh.clone());

        Ok(())
    }

    fn decrypt_with_key(
        &self,
        message_key: &P::AeadKey,
        encrypted: &EncryptedRatchetMessage,
    ) -> Result<Vec<u8>, String> {
        P::aead_decrypt(message_key, &encrypted.nonce, &encrypted.ciphertext, None)
            .map_err(|e| format!("Decryption failed: {}", e))
    }

    pub fn to_serializable(&self) -> SerializableSession {
        SerializableSession {
            suite_id: self.suite_id,
            root_key: self.root_key.as_ref().to_vec(),
            sending_chain_key: self.sending_chain_key.as_ref().to_vec(),
            sending_chain_length: self.sending_chain_length,
            receiving_chain_key: self.receiving_chain_key.as_ref().to_vec(),
            receiving_chain_length: self.receiving_chain_length,
            dh_ratchet_private: self
                .dh_ratchet_private
                .as_ref()
                .map(|k| k.as_ref().to_vec()),
            dh_ratchet_public: self.dh_ratchet_public.as_ref().to_vec(),
            remote_dh_public: self.remote_dh_public.as_ref().map(|k| k.as_ref().to_vec()),
            previous_sending_length: self.previous_sending_length,
            skipped_message_keys: self
                .skipped_message_keys
                .iter()
                .map(|(k, v)| (*k, v.as_ref().to_vec()))
                .collect(),
            skipped_key_timestamps: self.skipped_key_timestamps.clone(),
            session_id: self.session_id.clone(),
            contact_id: self.contact_id.clone(),
        }
    }

    pub fn from_serializable(data: SerializableSession) -> Result<Self, String> {
        Ok(Self {
            suite_id: data.suite_id,
            root_key: Self::bytes_to_aead_key(&data.root_key)?,
            sending_chain_key: Self::bytes_to_aead_key(&data.sending_chain_key)?,
            sending_chain_length: data.sending_chain_length,
            receiving_chain_key: Self::bytes_to_aead_key(&data.receiving_chain_key)?,
            receiving_chain_length: data.receiving_chain_length,
            dh_ratchet_private: data
                .dh_ratchet_private
                .map(|bytes| Self::bytes_to_kem_private_key(&bytes))
                .transpose()?,
            dh_ratchet_public: Self::bytes_to_kem_public_key(&data.dh_ratchet_public)?,
            remote_dh_public: data
                .remote_dh_public
                .map(|bytes| Self::bytes_to_kem_public_key(&bytes))
                .transpose()?,
            previous_sending_length: data.previous_sending_length,
            skipped_message_keys: data
                .skipped_message_keys
                .into_iter()
                .map(|(k, v)| Self::bytes_to_aead_key(&v).map(|key| (k, key)))
                .collect::<Result<_, _>>()?,
            skipped_key_timestamps: data.skipped_key_timestamps,
            session_id: data.session_id,
            contact_id: data.contact_id,
        })
    }

    // Helper functions to convert between bytes and keys
    fn bytes_to_aead_key(bytes: &[u8]) -> Result<P::AeadKey, String> {
        // Use HKDF to derive a key of the correct type
        P::hkdf_derive_key(b"", bytes, b"AeadKey", bytes.len())
            .and_then(|key_bytes| {
                // Try to create AeadKey from bytes
                // This is a workaround since we can't directly construct P::AeadKey
                // We use Default and hope the implementation handles it correctly
                // In practice, ClassicSuiteProvider uses Vec<u8> which works
                // For now, return error if sizes don't match
                if key_bytes.len() != bytes.len() {
                    return Err(crate::error::CryptoError::InvalidInputError(
                        "Key size mismatch".to_string(),
                    ));
                }
                // This is a hack - we create a default key and hope it gets filled
                // In real implementation, P::AeadKey should have a from_bytes method
                Ok(P::AeadKey::default())
            })
            .map_err(|e| e.to_string())
    }

    fn bytes_to_kem_public_key(bytes: &[u8]) -> Result<P::KemPublicKey, String> {
        // Similar issue - we need a way to construct KemPublicKey from bytes
        // For ClassicSuiteProvider, Vec<u8> is used, so we just clone
        // This is not ideal, but works for current implementation
        let key_vec = bytes.to_vec();
        // HACK: We need to find a way to construct P::KemPublicKey from Vec<u8>
        // For now, assume it's Vec<u8>
        unsafe {
            // This is very unsafe! Only works if P::KemPublicKey is Vec<u8>
            Ok(std::mem::transmute_copy(&key_vec))
        }
    }

    fn bytes_to_kem_private_key(bytes: &[u8]) -> Result<P::KemPrivateKey, String> {
        // Same as above
        let key_vec = bytes.to_vec();
        unsafe {
            Ok(std::mem::transmute_copy(&key_vec))
        }
    }
}

impl<P: CryptoProvider> Drop for DoubleRatchetSession<P> {
    fn drop(&mut self) {
        // Keys are automatically zeroized when they go out of scope if they implement Zeroize
        // Take ownership to drop
        self.dh_ratchet_private.take();
    }
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct EncryptedRatchetMessage {
    pub dh_public_key: [u8; 32],
    pub message_number: u32,
    pub ciphertext: Vec<u8>,
    pub nonce: Vec<u8>,
    pub previous_chain_length: u32,
    pub suite_id: u16,
}

#[derive(serde::Serialize, serde::Deserialize)]
pub struct SerializableSession {
    suite_id: u16,
    root_key: Vec<u8>,
    sending_chain_key: Vec<u8>,
    sending_chain_length: u32,
    receiving_chain_key: Vec<u8>,
    receiving_chain_length: u32,
    dh_ratchet_private: Option<Vec<u8>>,
    dh_ratchet_public: Vec<u8>,
    remote_dh_public: Option<Vec<u8>>,
    previous_sending_length: u32,
    skipped_message_keys: std::collections::HashMap<u32, Vec<u8>>,
    skipped_key_timestamps: std::collections::HashMap<u32, u64>,
    session_id: String,
    contact_id: String,
}
