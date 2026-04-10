fn main() {
    let manifest_dir = std::env::var("CARGO_MANIFEST_DIR")
        .expect("CARGO_MANIFEST_DIR must be set by cargo");
    let assets_dir = std::path::Path::new(&manifest_dir).join("assets");
    let out_dir = std::path::PathBuf::from(
        std::env::var("OUT_DIR").expect("OUT_DIR must be set by cargo"),
    );
    let out_file = out_dir.join("embedded_assets_rust.rs");

    println!("cargo:rerun-if-changed=assets");
    println!("cargo:rerun-if-changed=assets/index.html");
    println!("cargo:rerun-if-changed=assets/assets/app.css");
    println!("cargo:rerun-if-changed=assets/assets/app.js");
    println!("cargo:rustc-env=EMBEDDED_ASSETS_RUST={}", out_file.display());

    let assets = tauri_codegen::embedded_assets::EmbeddedAssets::new(
        assets_dir,
        &tauri_codegen::embedded_assets::AssetOptions::new(
            tauri_utils::config::PatternKind::Brownfield,
        ),
        |_key, _path, _input, _csp_hashes| {
            Ok::<(), tauri_codegen::embedded_assets::EmbeddedAssetsError>(())
        },
    )
    .expect("failed to generate embedded assets for the seam oracle");

    let mut tokens = proc_macro2::TokenStream::new();
    quote::ToTokens::to_tokens(&assets, &mut tokens);

    std::fs::write(&out_file, tokens.to_string())
        .unwrap_or_else(|error| panic!("failed to write embedded assets oracle output {out_file:?}: {error}"));
}
