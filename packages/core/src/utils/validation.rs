use crate::utils::error::Result;

pub fn validate_public_key(key: &[u8]) -> Result<()> {
    if key.len() != 32 {
        return Err(crate::utils::error::ConstructError::ValidationError(
            "Public key must be 32 bytes".to_string(),
        ));
    }
    Ok(())
}

pub fn validate_signature(sig: &[u8]) -> Result<()> {
    if sig.len() != 64 {
        return Err(crate::utils::error::ConstructError::ValidationError(
            "Signature must be 64 bytes".to_string(),
        ));
    }
    Ok(())
}
