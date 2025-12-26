use thiserror::Error;

#[derive(Error, Debug)]
pub enum CryptoError {
    #[error("Failed to generate keys: {0}")]
    KeyGenerationError(String),
    #[error("Signing failed: {0}")]
    SigningError(String),
    #[error("Signature verification failed: {0}")]
    SignatureVerificationError(String),
    #[error("KEM encapsulation failed: {0}")]
    KemEncapsulationError(String),
    #[error("KEM decapsulation failed: {0}")]
    KemDecapsulationError(String),
    #[error("AEAD encryption failed: {0}")]
    AeadEncryptionError(String),
    #[error("AEAD decryption failed: {0}")]
    AeadDecryptionError(String),
    #[error("Key derivation failed: {0}")]
    KeyDerivationError(String),
    #[error("Nonce generation failed: {0}")]
    NonceGenerationError(String),
    #[error("Invalid input: {0}")]
    InvalidInputError(String),
    #[error("Serialization error: {0}")]
    SerializationError(String),
    #[error("Deserialization error: {0}")]
    DeserializationError(String),
    #[error("Other crypto error: {0}")]
    Other(String),
}

impl From<chacha20poly1305::Error> for CryptoError {
    fn from(err: chacha20poly1305::Error) -> Self {
        CryptoError::AeadEncryptionError(err.to_string())
    }
}

impl From<ed25519_dalek::SignatureError> for CryptoError {
    fn from(err: ed25519_dalek::SignatureError) -> Self {
        CryptoError::SigningError(err.to_string())
    }
}

impl From<rand::Error> for CryptoError {
    fn from(err: rand::Error) -> Self {
        CryptoError::KeyGenerationError(err.to_string()) // General RNG error
    }
}
