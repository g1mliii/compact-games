use std::path::Path;

fn main() {
    println!("cargo:rerun-if-changed=src/api");
    println!("cargo:rerun-if-changed=src/frb_generated.rs");
    println!("cargo:rerun-if-changed=../flutter_rust_bridge.yaml");

    if !Path::new("src/frb_generated.rs").exists() {
        println!(
            "cargo:warning=FRB bindings missing. Run `pwsh ./scripts/generate-frb.ps1` from repo root."
        );
    }
}
