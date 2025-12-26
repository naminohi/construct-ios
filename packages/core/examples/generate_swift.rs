use std::fs;
use std::path::PathBuf;

fn main() {
    println!("Generating Swift bindings from UDL...");

    let udl_file = PathBuf::from("src/construct_core.udl");
    let out_dir = PathBuf::from("../../ConstructMessenger");

    // Read UDL file
    let udl = fs::read_to_string(&udl_file)
        .expect("Failed to read UDL file");

    // Generate Swift bindings
    let config = uniffi::Config::default();

    match uniffi::generate_bindings(
        &udl,
        Some(config),
        vec!["swift"],
        &out_dir,
        None,
        false,
    ) {
        Ok(_) => {
            println!("✅ Swift bindings generated successfully!");
            println!("   Location: {}", out_dir.display());
        }
        Err(e) => {
            eprintln!("❌ Failed to generate bindings: {}", e);
            std::process::exit(1);
        }
    }
}
