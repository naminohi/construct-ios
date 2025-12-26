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
    /// Выполняет X3DH обмен и возвращает root key
    /// Упрощенная версия без ephemeral ключа
    pub fn perform_x3dh(
        identity_private: &P::KemPrivateKey,
        _signed_prekey_private: &P::KemPrivateKey,
        remote_identity_public: &P::KemPublicKey,
        remote_signed_prekey_public: &P::KemPublicKey,
        remote_signature: &[u8],
        remote_verifying_key: &P::SignaturePublicKey,
        _remote_suite_id: SuiteID,
    ) -> Result<Vec<u8>, String> {
        eprintln!("[X3DH] perform_x3dh called");
        eprintln!("[X3DH] remote_signature length: {}", remote_signature.len());
        eprintln!("[X3DH] remote_signed_prekey_public length: {}", remote_signed_prekey_public.as_ref().len());
        eprintln!("[X3DH] remote_verifying_key length: {}", remote_verifying_key.as_ref().len());

        // 1. Верификация подписи
        eprintln!("[X3DH] Step 1: Starting signature verification...");
        eprintln!("[X3DH] Data to verify (first 10 bytes): {:?}", &remote_signed_prekey_public.as_ref()[..10.min(remote_signed_prekey_public.as_ref().len())]);
        eprintln!("[X3DH] Signature to verify (first 10 bytes): {:?}", &remote_signature[..10.min(remote_signature.len())]);
        eprintln!("[X3DH] Verifying key (first 10 bytes): {:?}", &remote_verifying_key.as_ref()[..10.min(remote_verifying_key.as_ref().len())]);

        P::verify(
            remote_verifying_key,
            remote_signed_prekey_public.as_ref(),
            remote_signature,
        )
        .map_err(|e| {
            eprintln!("[X3DH] ERROR: Signature verification failed: {}", e);
            format!("Signature verification failed: {}", e)
        })?;
        eprintln!("[X3DH] Step 1: Signature verified successfully");

        // 2. KEM decapsulation для получения shared secret
        // Для X25519 это будет DH, для PQ это будет KEM decapsulation
        eprintln!("[X3DH] Step 2: Starting KEM decapsulation...");
        eprintln!("[X3DH] remote_identity_public length: {}", remote_identity_public.as_ref().len());
        let shared_secret = P::kem_decapsulate(identity_private, remote_identity_public.as_ref())
            .map_err(|e| {
                eprintln!("[X3DH] ERROR: KEM decapsulation failed: {}", e);
                format!("KEM decapsulation failed: {}", e)
            })?;
        eprintln!("[X3DH] Step 2: KEM decapsulation completed, shared_secret length: {}", shared_secret.len());

        // 3. Вывод root key через HKDF
        eprintln!("[X3DH] Step 3: Starting HKDF derivation...");
        let root_key = P::hkdf_derive_key(
            b"", // no salt
            &shared_secret,
            b"X3DH Root Key",
            32, // 32 bytes root key
        )
        .map_err(|e| {
            eprintln!("[X3DH] ERROR: HKDF derivation failed: {}", e);
            format!("HKDF derivation failed: {}", e)
        })?;
        eprintln!("[X3DH] Step 3: HKDF derivation completed, root_key length: {}", root_key.len());

        eprintln!("[X3DH] perform_x3dh completed successfully");
        Ok(root_key)
    }

    /// Генерирует bundle для регистрации
    pub fn generate_registration_bundle() -> Result<RegistrationBundle, String> {
        eprintln!("[X3DH] generate_registration_bundle called");

        // Генерируем ключи через CryptoProvider
        let (identity_private, identity_public) =
            P::generate_kem_keys().map_err(|e| e.to_string())?;
        let (_signed_prekey_private, signed_prekey_public) =
            P::generate_kem_keys().map_err(|e| e.to_string())?;
        let (signing_key, verifying_key) =
            P::generate_signature_keys().map_err(|e| e.to_string())?;

        eprintln!("[X3DH] Generated keys:");
        eprintln!("[X3DH]   identity_public length: {}", identity_public.as_ref().len());
        eprintln!("[X3DH]   signed_prekey_public length: {}", signed_prekey_public.as_ref().len());
        eprintln!("[X3DH]   verifying_key length: {}", verifying_key.as_ref().len());

        // Подписываем signed prekey
        eprintln!("[X3DH] Signing signed_prekey_public...");
        eprintln!("[X3DH] Data to sign (first 10 bytes): {:?}", &signed_prekey_public.as_ref()[..10.min(signed_prekey_public.as_ref().len())]);
        let signature =
            P::sign(&signing_key, signed_prekey_public.as_ref()).map_err(|e| e.to_string())?;
        eprintln!("[X3DH] Signature created, length: {}", signature.len());
        eprintln!("[X3DH] Signature (first 10 bytes): {:?}", &signature[..10.min(signature.len())]);

        Ok(RegistrationBundle {
            identity_public: identity_public.as_ref().to_vec(),
            signed_prekey_public: signed_prekey_public.as_ref().to_vec(),
            signature,
            verifying_key: verifying_key.as_ref().to_vec(),
            suite_id: P::suite_id(),
        })
    }
}
