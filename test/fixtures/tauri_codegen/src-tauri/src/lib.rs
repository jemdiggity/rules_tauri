pub fn run() {
    let context: tauri::Context<tauri::Wry> = tauri::tauri_build_context!();
    assert!(
        context
            .assets()
            .get(&tauri::utils::assets::AssetKey::from("index.html"))
            .is_some(),
        "expected compressed embedded assets to resolve index.html at runtime"
    );
    let script_hashes = context
        .assets()
        .csp_hashes(&tauri::utils::assets::AssetKey::from("index.html"))
        .filter_map(|hash| match hash {
            tauri::utils::assets::CspHash::Script(value) => Some(value.to_string()),
            _ => None,
        })
        .collect::<Vec<_>>();
    assert_eq!(
        script_hashes,
        vec!["'sha256-Jl5nE06v62vFFK47dsthP8pGPv/wqI4pS/iJOPDBVJs='".to_string()],
        "expected Bazel-owned embedded assets seam to preserve Tauri CSP script hashes"
    );
}
