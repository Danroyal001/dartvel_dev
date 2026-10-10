fn main() {
    println!("cargo:rerun-if-changed=src/lib.rs");
    // The header describes the C ABI, which is the same for every target, and
    // is committed. A cross build skips regenerating it: cbindgen runs `cargo
    // metadata`, which inherits the target's rustflags (cargo-xwin's
    // lld-link, for one) and fails when it applies them to the host.
    if std::env::var("TARGET").ok() != std::env::var("HOST").ok() {
        return;
    }
    let crate_dir = std::env::var("CARGO_MANIFEST_DIR").unwrap();
    let config_path = format!("{crate_dir}/cbindgen.toml");
    let config = cbindgen::Config::from_file(&config_path).expect("load cbindgen config");

    cbindgen::Builder::new()
        .with_crate(crate_dir.clone())
        .with_config(config)
        .generate()
        .expect("cbindgen")
        .write_to_file(format!("{crate_dir}/include/dartvel_shelf.h"));
}
