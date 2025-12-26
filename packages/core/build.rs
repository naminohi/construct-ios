fn main() {
    // Generate UniFFI bindings
    uniffi::generate_scaffolding("src/construct_core.udl").unwrap();

    // Rerun if UDL file changes
    println!("cargo:rerun-if-changed=src/construct_core.udl");
}
