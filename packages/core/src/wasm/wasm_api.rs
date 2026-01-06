use wasm_bindgen::prelude::*;
use std::collections::HashMap;
use std::cell::RefCell;
use std::rc::Rc;
use uuid::Uuid;

use crate::state::app::{AppState, ConnectionState};
use crate::crypto::suites::classic::ClassicSuiteProvider;
use crate::utils::error::ConstructError;

// Use thread_local for single-threaded WASM context.
// Rc<RefCell<T>> is the standard pattern for shared mutable data on a single thread.
// - Rc: Allows multiple owners (cheaply cloneable reference count).
// - RefCell: Allows interior mutability (borrow/borrow_mut).
thread_local! {
    static APP_STATES: RefCell<HashMap<String, Rc<RefCell<AppState<ClassicSuiteProvider>>>>> = RefCell::new(HashMap::new());
}

// Internal helper to run a synchronous, non-mutating closure on an AppState.
fn with_app_state<F, T>(state_id: &str, f: F) -> Result<T, ConstructError>
where
    F: FnOnce(&mut AppState<ClassicSuiteProvider>) -> Result<T, ConstructError>,
{
    APP_STATES.with(|states_cell| {
        let states = states_cell.borrow();
        if let Some(state_rc) = states.get(state_id) {
            let mut state = state_rc.borrow_mut();
            f(&mut state)
        } else {
            Err(ConstructError::NotFound(format!("AppState with ID {} not found", state_id)))
        }
    })
}

// Internal helper for async operations.
// It clones the Rc to move ownership into the async block, avoiding borrow issues.
async fn with_app_state_async<F, Fut, T>(state_id: &str, f: F) -> Result<T, JsValue>
where
    F: FnOnce(Rc<RefCell<AppState<ClassicSuiteProvider>>>) -> Fut,
    Fut: std::future::Future<Output = Result<T, ConstructError>>,
{
    let state_rc = APP_STATES.with(|states_cell| {
        states_cell.borrow().get(state_id).cloned()
    });

    if let Some(rc) = state_rc {
        f(rc).await.map_err(Into::into)
    } else {
        Err(JsValue::from_str(&ConstructError::NotFound(format!("State {} not found", state_id)).to_string()))
    }
}


#[wasm_bindgen]
pub async fn create_app_state(db_name: String) -> Result<String, JsValue> {
    let _ = db_name;
    console_error_panic_hook::set_once();
    let state = AppState::<ClassicSuiteProvider>::new().await?;
    let state_id = Uuid::new_v4().to_string();
    let state_rc = Rc::new(RefCell::new(state));

    APP_STATES.with(|states_cell| {
        states_cell.borrow_mut().insert(state_id.clone(), state_rc);
    });
    Ok(state_id)
}

#[wasm_bindgen]
pub fn destroy_app_state(state_id: String) {
    APP_STATES.with(|states_cell| {
        states_cell.borrow_mut().remove(&state_id);
    });
}

type JsResult<T> = Result<T, JsValue>;

#[wasm_bindgen]
pub async fn app_state_initialize_user(state_id: String, username: String, password: String) -> JsResult<()> {
    with_app_state_async(&state_id, |cell| async move {
        cell.borrow_mut().initialize_user(username, password).await
    }).await
}

#[wasm_bindgen]
pub async fn app_state_finalize_registration(state_id: String, server_user_id: String, session_token: String, password: String) -> JsResult<()> {
    with_app_state_async(&state_id, |cell| async move {
        cell.borrow_mut().finalize_registration(server_user_id, session_token, password).await
    }).await
}

#[wasm_bindgen]
pub async fn app_state_load_user(state_id: String, user_id: String, password: String) -> JsResult<()> {
    with_app_state_async(&state_id, |cell| async move {
        cell.borrow_mut().load_user(user_id, password).await
    }).await
}

#[wasm_bindgen]
pub fn app_state_get_user_id(state_id: String) -> Option<String> {
    with_app_state(&state_id, |state| Ok(state.get_user_id().map(|s| s.to_string()))).unwrap_or(None)
}

#[wasm_bindgen]
pub fn app_state_get_username(state_id: String) -> Option<String> {
    with_app_state(&state_id, |state| Ok(state.get_username().map(|s| s.to_string()))).unwrap_or(None)
}

#[wasm_bindgen]
pub async fn app_state_add_contact(state_id: String, contact_id: String, username: String) -> JsResult<()> {
    with_app_state_async(&state_id, |cell| async move {
        cell.borrow_mut().add_contact(contact_id, username).await
    }).await
}

#[wasm_bindgen]
pub fn app_state_get_contacts(state_id: String) -> JsResult<JsValue> {
    let contacts_val = with_app_state(&state_id, |state| {
        let contacts = state.get_contacts();
        serde_json::to_value(contacts).map_err(|e| ConstructError::SerializationError(e.to_string()))
    })?;
    Ok(serde_wasm_bindgen::to_value(&contacts_val)?)
}

#[wasm_bindgen]
pub async fn app_state_send_message(state_id: String, to_contact_id: String, session_id: String, text: String) -> JsResult<String> {
    with_app_state_async(&state_id, |cell| async move {
        cell.borrow_mut().send_message(&to_contact_id, &session_id, &text).await
    }).await
}

#[wasm_bindgen]
pub async fn app_state_load_conversation(state_id: String, contact_id: String) -> JsResult<JsValue> {
    let conversation = with_app_state_async(&state_id, |cell| async move {
        cell.borrow_mut().load_conversation(&contact_id).await
    }).await?;
    Ok(serde_wasm_bindgen::to_value(&conversation)?)
}

#[wasm_bindgen]
pub fn app_state_connect(state_id: String, server_url: String) -> JsResult<()> {
    with_app_state(&state_id, |state| state.connect(&server_url)).map_err(Into::into)
}

#[wasm_bindgen]
pub fn app_state_disconnect(state_id: String) -> JsResult<()> {
    with_app_state(&state_id, |state| state.disconnect()).map_err(Into::into)
}

#[wasm_bindgen]
pub fn app_state_connection_state(state_id: String) -> String {
    with_app_state(&state_id, |state| {
        let state_val = match state.connection_state() {
            ConnectionState::Disconnected => "disconnected",
            ConnectionState::Connecting => "connecting",
            ConnectionState::Connected => "connected",
            ConnectionState::Reconnecting => "reconnecting",
            ConnectionState::Error => "error",
        };
        Ok(state_val.to_string())
    }).unwrap_or_else(|_| "error".to_string())
}

#[wasm_bindgen]
pub fn app_state_set_auto_reconnect(state_id: String, enabled: bool) {
    let _ = with_app_state(&state_id, |state| {
        state.reconnect_state_mut().set_enabled(enabled);
        Ok(())
    });
}

#[wasm_bindgen]
pub fn app_state_reconnect_attempts(state_id: String) -> u32 {
    with_app_state(&state_id, |state| Ok(state.reconnect_state().attempts())).unwrap_or(0)
}

#[wasm_bindgen]
pub fn app_state_reset_reconnect(state_id: String) {
    let _ = with_app_state(&state_id, |state| {
        state.reconnect_state_mut().reset();
        Ok(())
    });
}

#[wasm_bindgen]
pub fn app_state_register_on_server(state_id: String, password: String) -> JsResult<()> {
    with_app_state(&state_id, |state| state.register_on_server(password.clone())).map_err(Into::into)
}