#[cfg(target_arch = "wasm32")]
pub mod bindings;

#[cfg(target_arch = "wasm32")]
pub mod console;

#[cfg(target_arch = "wasm32")]
pub mod panic;
