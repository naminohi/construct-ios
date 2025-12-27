use crate::crypto::{CryptoProvider, SuiteID};
use serde::{Deserialize, Serialize};

#[derive(Serialize, Deserialize, Clone)]
pub struct PublicKeyBundle {
    pub identity_public: Vec<u8>,
    pub signed_prekey_public: Vec<u8>,
    pub signature: Vec<u8>,
    pub verifying_key: Vec<u8>,
    pub suite_id: SuiteID,
}

#[derive(Serialize, Deserialize, Clone)]
pub struct RegistrationBundle {
    pub identity_public: Vec<u8>,
    pub signed_prekey_public: Vec<u8>,
    pub signature: Vec<u8>,
    pub verifying_key: Vec<u8>,
    pub suite_id: SuiteID,
}

/// Чистая реализация X3DH протокола без состояния (generic по CryptoProvider)
pub struct X3DH<P: CryptoProvider> {
    _phantom: std::marker::PhantomData<P>,
}

impl<P: CryptoProvider> X3DH<P> {
    /// Выполняет полный X3DH обмен согласно Signal Protocol и возвращает root key
    ///
    /// Alice (инициатор):
    /// - IK_A: identity key Alice
    /// - EK_A: ephemeral key Alice (одноразовый)
    ///
    /// Bob (получатель):
    /// - IK_B: identity key Bob
    /// - SPK_B: signed prekey Bob
    ///
    /// X3DH Protocol:
    /// - DH1 = DH(IK_A, SPK_B)
    /// - DH2 = DH(EK_A, IK_B)
    /// - DH3 = DH(EK_A, SPK_B)
    /// - SK = KDF(DH1 || DH2 || DH3)
    pub fn perform_x3dh(
        identity_private: &P::KemPrivateKey,        // IK_A (Alice's identity private key)
        ephemeral_private: &P::KemPrivateKey,       // EK_A (Alice's ephemeral private key)
        remote_identity_public: &P::KemPublicKey,   // IK_B (Bob's identity public key)
        remote_signed_prekey_public: &P::KemPublicKey, // SPK_B (Bob's signed prekey)
        remote_signature: &[u8],                    // Signature over SPK_B
        remote_verifying_key: &P::SignaturePublicKey, // Bob's verifying key
        _remote_suite_id: SuiteID,
    ) -> Result<Vec<u8>, String> {
        use tracing::{debug, trace};

        debug!(target: "crypto::x3dh", "Starting X3DH key agreement");
        trace!(
            remote_signature_len = %remote_signature.len(),
            remote_spk_len = %remote_signed_prekey_public.as_ref().len(),
        );

        // 1. Verify signature on signed prekey
        debug!(target: "crypto::x3dh", "Step 1: Verifying signed prekey signature");
        P::verify(
            remote_verifying_key,
            remote_signed_prekey_public.as_ref(),
            remote_signature,
        )
        .map_err(|e| {
            debug!(target: "crypto::x3dh", error = %e, "Signature verification failed");
            format!("Signature verification failed: {}", e)
        })?;
        debug!(target: "crypto::x3dh", "Signature verified successfully");

        // 2. Perform three DH operations (Full X3DH)
        debug!(target: "crypto::x3dh", "Step 2: Performing DH operations");

        // DH1 = DH(IK_A, SPK_B)
        trace!(target: "crypto::x3dh", "Computing DH1 = DH(IK_A, SPK_B)");
        let dh1 = P::kem_decapsulate(identity_private, remote_signed_prekey_public.as_ref())
            .map_err(|e| format!("DH1 failed: {}", e))?;

        // DH2 = DH(EK_A, IK_B)
        trace!(target: "crypto::x3dh", "Computing DH2 = DH(EK_A, IK_B)");
        let dh2 = P::kem_decapsulate(ephemeral_private, remote_identity_public.as_ref())
            .map_err(|e| format!("DH2 failed: {}", e))?;

        // DH3 = DH(EK_A, SPK_B)
        trace!(target: "crypto::x3dh", "Computing DH3 = DH(EK_A, SPK_B)");
        let dh3 = P::kem_decapsulate(ephemeral_private, remote_signed_prekey_public.as_ref())
            .map_err(|e| format!("DH3 failed: {}", e))?;

        debug!(
            target: "crypto::x3dh",
            dh1_len = %dh1.len(),
            dh2_len = %dh2.len(),
            dh3_len = %dh3.len(),
            "DH operations completed"
        );

        // 3. Combine DH outputs: DH1 || DH2 || DH3
        let mut combined_dh = Vec::with_capacity(dh1.len() + dh2.len() + dh3.len());
        combined_dh.extend_from_slice(&dh1);
        combined_dh.extend_from_slice(&dh2);
        combined_dh.extend_from_slice(&dh3);

        // 4. Derive root key using HKDF
        debug!(target: "crypto::x3dh", "Step 3: Deriving root key with HKDF");
        let root_key = P::hkdf_derive_key(
            b"", // no salt
            &combined_dh,
            b"X3DH Root Key",
            32, // 32 bytes root key
        )
        .map_err(|e| format!("HKDF derivation failed: {}", e))?;

        debug!(
            target: "crypto::x3dh",
            root_key_len = %root_key.len(),
            "X3DH completed successfully"
        );

        Ok(root_key)
    }

    /// Выполняет X3DH для получателя (Bob)
    ///
    /// Bob (получатель):
    /// - IK_B: identity key Bob (private)
    /// - SPK_B: signed prekey Bob (private)
    ///
    /// Alice (инициатор):
    /// - IK_A: identity key Alice (public)
    /// - EK_A: ephemeral key Alice (public, из первого сообщения)
    ///
    /// Bob вычисляет:
    /// - DH1 = DH(SPK_B_priv, IK_A_pub)
    /// - DH2 = DH(IK_B_priv, EK_A_pub)
    /// - DH3 = DH(SPK_B_priv, EK_A_pub)
    /// - SK = KDF(DH1 || DH2 || DH3)
    pub fn perform_x3dh_receiver(
        local_identity_private: &P::KemPrivateKey,      // IK_B (Bob's identity private)
        local_signed_prekey_private: &P::KemPrivateKey, // SPK_B (Bob's signed prekey private)
        remote_identity_public: &P::KemPublicKey,       // IK_A (Alice's identity public)
        remote_ephemeral_public: &P::KemPublicKey,      // EK_A (Alice's ephemeral public from first msg)
    ) -> Result<Vec<u8>, String> {
        use tracing::{debug, trace};

        debug!(target: "crypto::x3dh", "Starting X3DH as receiver (Bob)");

        // DH1 = DH(SPK_B, IK_A)
        trace!(target: "crypto::x3dh", "Computing DH1 = DH(SPK_B, IK_A)");
        let dh1 = P::kem_decapsulate(local_signed_prekey_private, remote_identity_public.as_ref())
            .map_err(|e| format!("DH1 failed: {}", e))?;

        // DH2 = DH(IK_B, EK_A)
        trace!(target: "crypto::x3dh", "Computing DH2 = DH(IK_B, EK_A)");
        let dh2 = P::kem_decapsulate(local_identity_private, remote_ephemeral_public.as_ref())
            .map_err(|e| format!("DH2 failed: {}", e))?;

        // DH3 = DH(SPK_B, EK_A)
        trace!(target: "crypto::x3dh", "Computing DH3 = DH(SPK_B, EK_A)");
        let dh3 = P::kem_decapsulate(local_signed_prekey_private, remote_ephemeral_public.as_ref())
            .map_err(|e| format!("DH3 failed: {}", e))?;

        debug!(
            target: "crypto::x3dh",
            dh1_len = %dh1.len(),
            dh2_len = %dh2.len(),
            dh3_len = %dh3.len(),
            "DH operations completed (receiver)"
        );

        // Combine DH outputs: DH1 || DH2 || DH3
        let mut combined_dh = Vec::with_capacity(dh1.len() + dh2.len() + dh3.len());
        combined_dh.extend_from_slice(&dh1);
        combined_dh.extend_from_slice(&dh2);
        combined_dh.extend_from_slice(&dh3);

        // Derive root key using HKDF
        debug!(target: "crypto::x3dh", "Deriving root key with HKDF");
        let root_key = P::hkdf_derive_key(
            b"",
            &combined_dh,
            b"X3DH Root Key",
            32,
        )
        .map_err(|e| format!("HKDF derivation failed: {}", e))?;

        debug!(
            target: "crypto::x3dh",
            root_key_len = %root_key.len(),
            "X3DH completed successfully (receiver)"
        );

        Ok(root_key)
    }

    /// Генерирует bundle для регистрации
    pub fn generate_registration_bundle() -> Result<RegistrationBundle, String> {
        use tracing::debug;

        debug!(target: "crypto::x3dh", "Generating registration bundle");

        // Генерируем ключи через CryptoProvider
        let (_identity_private, identity_public) =
            P::generate_kem_keys().map_err(|e| e.to_string())?;
        let (_signed_prekey_private, signed_prekey_public) =
            P::generate_kem_keys().map_err(|e| e.to_string())?;
        let (signing_key, verifying_key) =
            P::generate_signature_keys().map_err(|e| e.to_string())?;

        debug!(
            target: "crypto::x3dh",
            identity_pk_len = %identity_public.as_ref().len(),
            signed_prekey_pk_len = %signed_prekey_public.as_ref().len(),
            verifying_key_len = %verifying_key.as_ref().len(),
            "Generated keys"
        );

        // Подписываем signed prekey
        debug!(target: "crypto::x3dh", "Signing signed prekey");
        let signature =
            P::sign(&signing_key, signed_prekey_public.as_ref()).map_err(|e| e.to_string())?;

        debug!(
            target: "crypto::x3dh",
            signature_len = %signature.len(),
            "Registration bundle created successfully"
        );

        Ok(RegistrationBundle {
            identity_public: identity_public.as_ref().to_vec(),
            signed_prekey_public: signed_prekey_public.as_ref().to_vec(),
            signature,
            verifying_key: verifying_key.as_ref().to_vec(),
            suite_id: P::suite_id(),
        })
    }
}
