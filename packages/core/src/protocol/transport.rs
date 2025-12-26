// WebSocket транспорт
// Обертка над браузерным WebSocket API для WASM

use crate::utils::error::{ConstructError, Result};

#[cfg(target_arch = "wasm32")]
use crate::protocol::{
    messages::{ClientMessage, ServerMessage},
    wire::{pack_client_message, unpack_server_message},
};
#[cfg(target_arch = "wasm32")]
use wasm_bindgen::prelude::*;
#[cfg(target_arch = "wasm32")]
use wasm_bindgen::JsCast;
#[cfg(target_arch = "wasm32")]
use web_sys::{CloseEvent, ErrorEvent, MessageEvent, WebSocket};

/// Состояние WebSocket соединения
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ConnectionState {
    Connecting,
    Connected,
    Disconnecting,
    Disconnected,
}

/// WebSocket транспорт для WASM
#[cfg(target_arch = "wasm32")]
pub struct WebSocketTransport {
    ws: Option<WebSocket>,
    state: ConnectionState,
}

#[cfg(target_arch = "wasm32")]
impl WebSocketTransport {
    /// Создать новый WebSocket транспорт
    pub fn new() -> Self {
        Self {
            ws: None,
            state: ConnectionState::Disconnected,
        }
    }

    /// Подключиться к серверу
    pub fn connect(&mut self, url: &str) -> Result<()> {
        if self.state == ConnectionState::Connected {
            return Err(ConstructError::NetworkError(
                "Already connected".to_string(),
            ));
        }

        let ws = WebSocket::new(url).map_err(|e| {
            ConstructError::NetworkError(format!("Failed to create WebSocket: {:?}", e))
        })?;

        // Установить binary тип для MessagePack
        ws.set_binary_type(web_sys::BinaryType::Arraybuffer);

        self.ws = Some(ws);
        self.state = ConnectionState::Connecting;

        Ok(())
    }

    /// Отправить сообщение
    pub fn send(&self, message: &ClientMessage) -> Result<()> {
        let ws = self
            .ws
            .as_ref()
            .ok_or_else(|| ConstructError::NetworkError("WebSocket not initialized".to_string()))?;

        // Проверить реальное состояние WebSocket (OPEN = 1)
        if ws.ready_state() != 1 {
            return Err(ConstructError::NetworkError("Not connected".to_string()));
        }

        // Сериализовать в MessagePack
        let packed = pack_client_message(message)?;

        // Отправить как ArrayBuffer
        ws.send_with_u8_array(&packed).map_err(|e| {
            ConstructError::NetworkError(format!("Failed to send message: {:?}", e))
        })?;

        Ok(())
    }

    /// Закрыть соединение
    pub fn close(&mut self) -> Result<()> {
        if let Some(ws) = &self.ws {
            ws.close()
                .map_err(|e| ConstructError::NetworkError(format!("Failed to close: {:?}", e)))?;
            self.state = ConnectionState::Disconnecting;
        }
        Ok(())
    }

    /// Получить текущее состояние соединения
    pub fn state(&self) -> ConnectionState {
        self.state
    }

    /// Проверить, подключен ли транспорт
    pub fn is_connected(&self) -> bool {
        self.ws
            .as_ref()
            .map(|ws| ws.ready_state() == 1)
            .unwrap_or(false)
    }

    /// Установить callback для onopen
    pub fn set_on_open<F>(&self, callback: F) -> Result<()>
    where
        F: Fn() + 'static,
    {
        let ws = self
            .ws
            .as_ref()
            .ok_or_else(|| ConstructError::NetworkError("WebSocket not initialized".to_string()))?;

        let closure = Closure::wrap(Box::new(move |_event: JsValue| {
            callback();
        }) as Box<dyn Fn(JsValue)>);

        ws.set_onopen(Some(closure.as_ref().unchecked_ref()));
        closure.forget();

        Ok(())
    }

    /// Установить callback для onmessage (принимает ServerMessage от сервера)
    pub fn set_on_message<F>(&self, callback: F) -> Result<()>
    where
        F: Fn(ServerMessage) + 'static,
    {
        let ws = self
            .ws
            .as_ref()
            .ok_or_else(|| ConstructError::NetworkError("WebSocket not initialized".to_string()))?;

        let closure = Closure::wrap(Box::new(move |event: MessageEvent| {
            if let Ok(array_buffer) = event.data().dyn_into::<js_sys::ArrayBuffer>() {
                let uint8_array = js_sys::Uint8Array::new(&array_buffer);
                let data = uint8_array.to_vec();

                match unpack_server_message(&data) {
                    Ok(msg) => callback(msg),
                    Err(e) => {
                        #[cfg(feature = "wasm")]
                        crate::wasm::console::log(&format!(
                            "Failed to unpack server message: {:?}",
                            e
                        ));
                    }
                }
            }
        }) as Box<dyn Fn(MessageEvent)>);

        ws.set_onmessage(Some(closure.as_ref().unchecked_ref()));
        closure.forget();

        Ok(())
    }

    /// Установить callback для onerror
    pub fn set_on_error<F>(&self, callback: F) -> Result<()>
    where
        F: Fn(String) + 'static,
    {
        let ws = self
            .ws
            .as_ref()
            .ok_or_else(|| ConstructError::NetworkError("WebSocket not initialized".to_string()))?;

        let closure = Closure::wrap(Box::new(move |_event: ErrorEvent| {
            callback("WebSocket error occurred".to_string());
        }) as Box<dyn Fn(ErrorEvent)>);

        ws.set_onerror(Some(closure.as_ref().unchecked_ref()));
        closure.forget();

        Ok(())
    }

    /// Установить callback для onclose
    pub fn set_on_close<F>(&self, callback: F) -> Result<()>
    where
        F: Fn(u16, String) + 'static,
    {
        let ws = self
            .ws
            .as_ref()
            .ok_or_else(|| ConstructError::NetworkError("WebSocket not initialized".to_string()))?;

        let closure = Closure::wrap(Box::new(move |event: CloseEvent| {
            let code = event.code();
            let reason = event.reason();
            callback(code, reason);
        }) as Box<dyn Fn(CloseEvent)>);

        ws.set_onclose(Some(closure.as_ref().unchecked_ref()));
        closure.forget();

        Ok(())
    }
}

/// Заглушка для не-WASM платформ
#[cfg(not(target_arch = "wasm32"))]
use crate::protocol::messages::ClientMessage;
#[cfg(not(target_arch = "wasm32"))]
pub struct WebSocketTransport {
    state: ConnectionState,
}

#[cfg(not(target_arch = "wasm32"))]
impl WebSocketTransport {
    pub fn new() -> Self {
        Self {
            state: ConnectionState::Disconnected,
        }
    }

    pub fn connect(&mut self, _url: &str) -> Result<()> {
        Err(ConstructError::NetworkError(
            "WebSocket transport only available in WASM target".to_string(),
        ))
    }

    pub fn send(&self, _message: &ClientMessage) -> Result<()> {
        Err(ConstructError::NetworkError(
            "WebSocket transport only available in WASM target".to_string(),
        ))
    }

    pub fn close(&mut self) -> Result<()> {
        Err(ConstructError::NetworkError(
            "WebSocket transport only available in WASM target".to_string(),
        ))
    }

    pub fn state(&self) -> ConnectionState {
        self.state
    }

    pub fn is_connected(&self) -> bool {
        false
    }
}

#[cfg(not(target_arch = "wasm32"))]
impl Default for WebSocketTransport {
    fn default() -> Self {
        Self::new()
    }
}
