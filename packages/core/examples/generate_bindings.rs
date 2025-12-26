// Simple tool to generate Swift bindings

fn main() {
    uniffi::generate_bindings(
        "src/construct_core.udl",
        None,
        vec!["swift"],
        Some("../../ConstructMessenger"),
        None,
        false,
    ).unwrap();

    println!("Swift bindings generated in ../../ConstructMessenger");
}
