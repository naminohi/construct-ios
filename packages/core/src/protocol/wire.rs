// Wire format (MessagePack сериализация)
// Используется для передачи сообщений через WebSocket

use crate::protocol::messages::{ClientMessage, ServerMessage};
use crate::utils::error::{ConstructError, Result};
use rmp_serde::{Deserializer, Serializer};
use serde::{Deserialize, Serialize};

/// Упаковать ClientMessage в MessagePack формат (клиент -> сервер)
pub fn pack_client_message(message: &ClientMessage) -> Result<Vec<u8>> {
    let mut buffer = Vec::new();
    message
        .serialize(&mut Serializer::new(&mut buffer))
        .map_err(|e| {
            ConstructError::SerializationError(format!("MessagePack pack error: {}", e))
        })?;
    Ok(buffer)
}

/// Распаковать MessagePack в ServerMessage (сервер -> клиент)
pub fn unpack_server_message(data: &[u8]) -> Result<ServerMessage> {
    let mut deserializer = Deserializer::new(data);
    ServerMessage::deserialize(&mut deserializer)
        .map_err(|e| ConstructError::SerializationError(format!("MessagePack unpack error: {}", e)))
}

/// Упаковать произвольные данные в MessagePack
pub fn pack_raw<T: Serialize>(data: &T) -> Result<Vec<u8>> {
    let mut buffer = Vec::new();
    data.serialize(&mut Serializer::new(&mut buffer))
        .map_err(|e| {
            ConstructError::SerializationError(format!("MessagePack pack error: {}", e))
        })?;
    Ok(buffer)
}

/// Распаковать MessagePack в произвольный тип
pub fn unpack_raw<'a, T: Deserialize<'a>>(data: &'a [u8]) -> Result<T> {
    let mut deserializer = Deserializer::new(data);
    T::deserialize(&mut deserializer)
        .map_err(|e| ConstructError::SerializationError(format!("MessagePack unpack error: {}", e)))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::protocol::messages::RegisterData;

    #[test]
    fn test_pack_unpack_client_message() {
        let msg = ClientMessage::Register(RegisterData {
            username: "test".to_string(),
            password: "password".to_string(),
            public_key: "key".to_string(),
        });
        let packed = pack_client_message(&msg).unwrap();
        assert!(!packed.is_empty());
    }
}
