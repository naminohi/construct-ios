//! X3DH (Extended Triple Diffie-Hellman) Protocol
//!
//! Реализация протокола установки ключей из Signal Protocol.
//!
//! ## Обзор
//!
//! X3DH обеспечивает:
//! - **Forward Secrecy**: Ephemeral keys для каждой сессии
//! - **Cryptographic Deniability**: Подписи только на долгосрочных ключах
//! - **Asynchronous**: Bob может быть offline
//!
//! ## Ключи
//!
//! ### Alice (инициатор)
//! - **IK_A**: Identity Key (долгосрочный)
//! - **EK_A**: Ephemeral Key (одноразовый, генерируется для каждой сессии)
//!
//! ### Bob (получатель)
//! - **IK_B**: Identity Key (долгосрочный)
//! - **SPK_B**: Signed Prekey (среднесрочный, ротируется)
//! - **Sig(SPK_B)**: Подпись SPK_B от Signing Key
//!
//! ## Протокол
//!
//! ```text
//! Alice                                                Bob
//! =====                                                ===
//!
//! 1. Генерирует EK_A
//! 2. Получает (IK_B_pub, SPK_B_pub, Sig) от сервера
//! 3. Проверяет Sig(SPK_B_pub)
//! 4. Вычисляет:
//!    DH1 = DH(IK_A, SPK_B)
//!    DH2 = DH(EK_A, IK_B)
//!    DH3 = DH(EK_A, SPK_B)
//!    SK = KDF(DH1 || DH2 || DH3)
//!
//! 5. Отправляет первое сообщение с EK_A_pub →
//!
//!                                                      1. Получает первое сообщение
//!                                                      2. Извлекает EK_A_pub из сообщения
//!                                                      3. Получает IK_A_pub от сервера
//!                                                      4. Вычисляет (те же DH, но reverse):
//!                                                         DH1 = DH(SPK_B, IK_A)
//!                                                         DH2 = DH(IK_B, EK_A)
//!                                                         DH3 = DH(SPK_B, EK_A)
//!                                                         SK = KDF(DH1 || DH2 || DH3)
//!
//! SK_Alice = SK_Bob (одинаковые!)
//! ```
//!
//! ## Математика
//!
//! Diffie-Hellman обладает коммутативностью:
//! ```text
//! DH(a, B) = a × B = a × (b × G) = (a × b) × G
//! DH(b, A) = b × A = b × (a × G) = (b × a) × G = (a × b) × G
//!
//! Поэтому: DH(a, B) = DH(b, A)
//! ```

use crate::crypto::handshake::{InitiatorState, KeyAgreement};
use crate::crypto::provider::CryptoProvider;
use crate::crypto::SuiteID;
use serde::{Deserialize, Serialize};
use std::marker::PhantomData;

/// Публичные ключи для инициации сессии
///
/// Alice получает этот bundle от сервера перед началом handshake с Bob.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct X3DHPublicKeyBundle {
    /// Bob's Identity Public Key (IK_B_pub)
    pub identity_public: Vec<u8>,

    /// Bob's Signed Prekey Public Key (SPK_B_pub)
    pub signed_prekey_public: Vec<u8>,

    /// Signature over signed_prekey_public (Sig(SPK_B))
    pub signature: Vec<u8>,

    /// Bob's Verifying Key для проверки подписи
    pub verifying_key: Vec<u8>,

    /// Crypto suite ID
    pub suite_id: SuiteID,
}

/// Регистрационные данные для отправки на сервер
///
/// Пользователь генерирует этот bundle при регистрации и отправляет на сервер.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct X3DHRegistrationBundle {
    /// User's Identity Public Key (IK_pub)
    pub identity_public: Vec<u8>,

    /// User's Signed Prekey Public Key (SPK_pub)
    pub signed_prekey_public: Vec<u8>,

    /// Signature over signed_prekey_public (Sig(SPK))
    pub signature: Vec<u8>,

    /// User's Verifying Key
    pub verifying_key: Vec<u8>,

    /// Crypto suite ID
    pub suite_id: SuiteID,
}

/// X3DH Protocol Implementation
///
/// Stateless struct - все данные передаются через параметры методов.
pub struct X3DHProtocol<P: CryptoProvider> {
    _phantom: PhantomData<P>,
}

impl<P: CryptoProvider> KeyAgreement<P> for X3DHProtocol<P> {
    type RegistrationBundle = X3DHRegistrationBundle;
    type PublicKeyBundle = X3DHPublicKeyBundle;
    type SharedSecret = Vec<u8>; // 32 bytes root key

    fn generate_registration_bundle() -> Result<Self::RegistrationBundle, String> {
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

        Ok(X3DHRegistrationBundle {
            identity_public: identity_public.as_ref().to_vec(),
            signed_prekey_public: signed_prekey_public.as_ref().to_vec(),
            signature,
            verifying_key: verifying_key.as_ref().to_vec(),
            suite_id: P::suite_id(),
        })
    }

    fn perform_as_initiator(
        local_identity: &P::KemPrivateKey,
        remote_bundle: &Self::PublicKeyBundle,
    ) -> Result<(Self::SharedSecret, InitiatorState<P>), String> {
        use tracing::{debug, trace};

        debug!(target: "crypto::x3dh", "Starting X3DH as initiator (Alice)");
        trace!(suite_id = %remote_bundle.suite_id);

        // ===================================================================
        // ВАЖНО: Генерируем ephemeral key для этой сессии (Forward Secrecy!)
        // ===================================================================
        debug!(target: "crypto::x3dh", "Generating ephemeral key for this session");
        let (ephemeral_private, ephemeral_public) = P::generate_kem_keys()
            .map_err(|e| format!("Failed to generate ephemeral key: {}", e))?;

        trace!(
            ephemeral_public_len = %ephemeral_public.as_ref().len(),
            "Ephemeral key generated"
        );

        // Parse remote keys from bundle
        let remote_identity_public = P::kem_public_key_from_bytes(remote_bundle.identity_public.clone());
        let remote_signed_prekey_public = P::kem_public_key_from_bytes(remote_bundle.signed_prekey_public.clone());
        let remote_verifying_key = P::signature_public_key_from_bytes(remote_bundle.verifying_key.clone());

        // 1. Verify signature on signed prekey
        debug!(target: "crypto::x3dh", "Step 1: Verifying signed prekey signature");
        P::verify(
            &remote_verifying_key,
            remote_signed_prekey_public.as_ref(),
            &remote_bundle.signature,
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
        let dh1 = P::kem_decapsulate(local_identity, remote_signed_prekey_public.as_ref())
            .map_err(|e| format!("DH1 failed: {}", e))?;

        // DH2 = DH(EK_A, IK_B)
        trace!(target: "crypto::x3dh", "Computing DH2 = DH(EK_A, IK_B)");
        let dh2 = P::kem_decapsulate(&ephemeral_private, remote_identity_public.as_ref())
            .map_err(|e| format!("DH2 failed: {}", e))?;

        // DH3 = DH(EK_A, SPK_B)
        trace!(target: "crypto::x3dh", "Computing DH3 = DH(EK_A, SPK_B)");
        let dh3 = P::kem_decapsulate(&ephemeral_private, remote_signed_prekey_public.as_ref())
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
            "X3DH completed successfully as initiator"
        );

        // ===================================================================
        // ВАЖНО: Возвращаем ephemeral_private в InitiatorState
        // Он будет использован как первый DH ratchet key в Double Ratchet!
        // ===================================================================
        let initiator_state = InitiatorState {
            ephemeral_private,
        };

        Ok((root_key, initiator_state))
    }

    fn perform_as_responder(
        local_identity: &P::KemPrivateKey,
        local_signed_prekey: &P::KemPrivateKey,
        remote_identity: &P::KemPublicKey,
        remote_ephemeral: &P::KemPublicKey,
    ) -> Result<Self::SharedSecret, String> {
        use tracing::{debug, trace};

        debug!(target: "crypto::x3dh", "Starting X3DH as responder (Bob)");

        // Perform three DH operations (Bob's perspective)
        // Bob вычисляет те же DH секреты, но с другой стороны

        // DH1 = DH(SPK_B, IK_A)
        trace!(target: "crypto::x3dh", "Computing DH1 = DH(SPK_B, IK_A)");
        let dh1 = P::kem_decapsulate(local_signed_prekey, remote_identity.as_ref())
            .map_err(|e| format!("DH1 failed: {}", e))?;

        // DH2 = DH(IK_B, EK_A)
        trace!(target: "crypto::x3dh", "Computing DH2 = DH(IK_B, EK_A)");
        let dh2 = P::kem_decapsulate(local_identity, remote_ephemeral.as_ref())
            .map_err(|e| format!("DH2 failed: {}", e))?;

        // DH3 = DH(SPK_B, EK_A)
        trace!(target: "crypto::x3dh", "Computing DH3 = DH(SPK_B, EK_A)");
        let dh3 = P::kem_decapsulate(local_signed_prekey, remote_ephemeral.as_ref())
            .map_err(|e| format!("DH3 failed: {}", e))?;

        debug!(
            target: "crypto::x3dh",
            dh1_len = %dh1.len(),
            dh2_len = %dh2.len(),
            dh3_len = %dh3.len(),
            "DH operations completed (responder)"
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
            "X3DH completed successfully (responder)"
        );

        Ok(root_key)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::crypto::suites::classic::ClassicSuiteProvider;

    #[test]
    fn test_x3dh_alice_bob_get_same_root_key() {
        // Bob регистрируется
        let bob_bundle = X3DHProtocol::<ClassicSuiteProvider>::generate_registration_bundle().unwrap();

        // В реальности Bob сохраняет private keys, а public bundle идёт на сервер
        // Для теста мы эмулируем это через повторную генерацию с теми же ключами

        // Alice генерирует свои ключи
        let (alice_identity_priv, alice_identity_pub) = ClassicSuiteProvider::generate_kem_keys().unwrap();

        // Bob генерирует ключи (эмуляция - в реальности уже есть)
        let (bob_identity_priv, bob_identity_pub) = ClassicSuiteProvider::generate_kem_keys().unwrap();
        let (bob_signed_prekey_priv, bob_signed_prekey_pub) = ClassicSuiteProvider::generate_kem_keys().unwrap();
        let (bob_signing_key, bob_verifying_key) = ClassicSuiteProvider::generate_signature_keys().unwrap();

        // Bob подписывает свой signed prekey
        let bob_signature = ClassicSuiteProvider::sign(&bob_signing_key, bob_signed_prekey_pub.as_ref()).unwrap();

        // Alice получает Bob's public bundle от сервера
        let bob_public_bundle = X3DHPublicKeyBundle {
            identity_public: bob_identity_pub,
            signed_prekey_public: bob_signed_prekey_pub.clone(),
            signature: bob_signature,
            verifying_key: bob_verifying_key,
            suite_id: ClassicSuiteProvider::suite_id(),
        };

        // Alice выполняет X3DH как initiator
        let (alice_root_key, alice_state) = X3DHProtocol::<ClassicSuiteProvider>::perform_as_initiator(
            &alice_identity_priv,
            &bob_public_bundle,
        ).unwrap();

        // Alice отправляет первое сообщение с ephemeral_public
        let alice_ephemeral_pub = ClassicSuiteProvider::from_private_key_to_public_key(&alice_state.ephemeral_private).unwrap();

        // Bob получает Alice's ephemeral public key из первого сообщения
        // Bob выполняет X3DH как responder
        let bob_root_key = X3DHProtocol::<ClassicSuiteProvider>::perform_as_responder(
            &bob_identity_priv,
            &bob_signed_prekey_priv,
            &alice_identity_pub,
            &alice_ephemeral_pub,
        ).unwrap();

        // ПРОВЕРКА: Alice и Bob должны получить ОДИНАКОВЫЙ root key
        assert_eq!(alice_root_key, bob_root_key, "X3DH must produce same root key for Alice and Bob");
        assert_eq!(alice_root_key.len(), 32, "Root key must be 32 bytes");
    }

    #[test]
    fn test_x3dh_rejects_invalid_signature() {
        let (alice_identity_priv, _) = ClassicSuiteProvider::generate_kem_keys().unwrap();

        // Bob's bundle с невалидной подписью
        let (_, bob_identity_pub) = ClassicSuiteProvider::generate_kem_keys().unwrap();
        let (_, bob_signed_prekey_pub) = ClassicSuiteProvider::generate_kem_keys().unwrap();
        let (_, bob_verifying_key) = ClassicSuiteProvider::generate_signature_keys().unwrap();

        let malicious_bundle = X3DHPublicKeyBundle {
            identity_public: bob_identity_pub,
            signed_prekey_public: bob_signed_prekey_pub,
            signature: vec![0xFF; 64], // Невалидная подпись
            verifying_key: bob_verifying_key,
            suite_id: ClassicSuiteProvider::suite_id(),
        };

        // Alice должна отклонить невалидную подпись
        let result = X3DHProtocol::<ClassicSuiteProvider>::perform_as_initiator(
            &alice_identity_priv,
            &malicious_bundle,
        );

        assert!(result.is_err(), "X3DH must reject invalid signature");

        match result {
            Err(e) => assert!(e.contains("Signature verification failed"), "Error message: {}", e),
            Ok(_) => panic!("Expected error but got Ok"),
        }
    }
}
