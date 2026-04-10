fn main() {
    if let Ok(manifest_dir) = std::env::var("CARGO_MANIFEST_DIR") {
        std::env::set_current_dir(&manifest_dir)
            .unwrap_or_else(|error| panic!("failed to chdir to {manifest_dir}: {error}"));
    }

    if let Ok(frontend_dist) = std::env::var("RULES_TAURI_FRONTEND_DIST") {
        let config_patch = serde_json::json!({
            "build": {
                "frontendDist": frontend_dist,
            },
        });
        std::env::set_var("TAURI_CONFIG", config_patch.to_string());
    }
    println!("cargo:rerun-if-env-changed=RULES_TAURI_FRONTEND_DIST");

    let attributes = tauri_build::Attributes::new().codegen(tauri_build::CodegenContext::new());
    tauri_build::try_build(attributes).expect("failed to generate Tauri build context");
}
