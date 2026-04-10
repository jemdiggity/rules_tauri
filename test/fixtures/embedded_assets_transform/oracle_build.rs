use base64::Engine;
use serde_json::json;
use sha2::{Digest, Sha256};
use std::collections::BTreeMap;

fn normalize_script_for_csp(input: &[u8]) -> Vec<u8> {
    tauri_utils::html2::normalize_script_for_csp(input)
}

fn hash_script(bytes: &[u8]) -> String {
    let hash = Sha256::digest(bytes);
    format!(
        "'sha256-{}'",
        base64::engine::general_purpose::STANDARD.encode(hash)
    )
}

fn asset_key(root: &std::path::Path, path: &std::path::Path) -> String {
    let relative = path.strip_prefix(root).unwrap();
    let parts = relative
        .components()
        .map(|component| component.as_os_str().to_string_lossy().into_owned())
        .collect::<Vec<_>>();
    format!("/{}", parts.join("/"))
}

fn main() {
    let manifest_dir =
        std::env::var("CARGO_MANIFEST_DIR").expect("CARGO_MANIFEST_DIR must be set by cargo");
    let assets_dir = std::path::Path::new(&manifest_dir).join("assets");
    let stable_file = std::path::Path::new(&manifest_dir).join("embedded_assets_transform.oracle.json");

    let mut assets = BTreeMap::<String, String>::new();
    let mut global_script_hashes = Vec::<String>::new();
    let mut html_inline_hashes = BTreeMap::<String, Vec<String>>::new();

    let mut paths = walkdir::WalkDir::new(&assets_dir)
        .follow_links(true)
        .into_iter()
        .filter_map(Result::ok)
        .filter(|entry| entry.file_type().is_file())
        .map(|entry| entry.into_path())
        .collect::<Vec<_>>();
    paths.sort();

    for path in paths {
        let key = asset_key(&assets_dir, &path);
        let mut input = std::fs::read(&path).expect("failed to read fixture asset");

        match path.extension().and_then(|ext| ext.to_str()) {
            Some("js") | Some("mjs") => {
                global_script_hashes.push(hash_script(&normalize_script_for_csp(&input)));
            }
            Some("html") => {
                let document = tauri_utils::html2::parse_doc(String::from_utf8_lossy(&input).into_owned());
                tauri_utils::html2::inject_nonce_token(
                    &document,
                    &tauri_utils::config::DisabledCspModificationKind::Flag(false),
                );
                let hashes = document
                    .select("script:not(:empty)")
                    .iter()
                    .map(|element| hash_script(&normalize_script_for_csp(element.text().as_bytes())))
                    .collect::<Vec<_>>();
                if !hashes.is_empty() {
                    html_inline_hashes.insert(key.clone(), hashes);
                }
                input = tauri_utils::html2::serialize_doc(&document);
            }
            _ => {}
        }

        assets.insert(
            key,
            String::from_utf8_lossy(&input).into_owned(),
        );
    }

    let output = json!({
        "assets": assets,
        "global_script_hashes": global_script_hashes,
        "html_inline_hashes": html_inline_hashes,
    });

    std::fs::write(&stable_file, serde_json::to_vec_pretty(&output).unwrap())
        .unwrap_or_else(|error| panic!("failed to write oracle transform output {stable_file:?}: {error}"));
}
