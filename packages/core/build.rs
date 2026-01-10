use std::fs;
use std::path::PathBuf;

fn main() {
    // Generate UniFFI bindings
    uniffi::generate_scaffolding("src/construct_core.udl").unwrap();

    // Patch generated file for Rust 1.82+ compatibility
    patch_uniffi_file();

    // Rerun if UDL file changes
    println!("cargo:rerun-if-changed=src/construct_core.udl");
}

fn patch_uniffi_file() {
    let out_dir = PathBuf::from(std::env::var("OUT_DIR").unwrap());
    let uniffi_file = out_dir.join("construct_core.uniffi.rs");

    if !uniffi_file.exists() {
        eprintln!("Warning: UniFFI file not found at {:?}", uniffi_file);
        return;
    }

    let content = fs::read_to_string(&uniffi_file)
        .expect("Failed to read UniFFI generated file");

    // Replace #[no_mangle] with #[unsafe(no_mangle)]
    let patched = content
        .replace("#[no_mangle]", "#[unsafe(no_mangle)]")
        .replace("#[export_name =", "#[unsafe(export_name =");

    fs::write(&uniffi_file, patched)
        .expect("Failed to write patched UniFFI file");

    println!("cargo:warning=Patched UniFFI file for Rust 1.82+ compatibility");
}
