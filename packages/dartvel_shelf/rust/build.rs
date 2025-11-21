fn main() {
    let crate_dir = std::env::var("CARGO_MANIFEST_DIR").unwrap();
    let config_path = format!("{crate_dir}/cbindgen.toml");
    let config = cbindgen::Config::from_file(&config_path).expect("load cbindgen config");

    cbindgen::Builder::new()
        .with_crate(crate_dir.clone())
        .with_config(config)
        .generate()
        .expect("cbindgen")
        .write_to_file(format!("{crate_dir}/include/dartvel_shelf.h"));
    println!("cargo:rerun-if-changed=src/lib.rs");
}
