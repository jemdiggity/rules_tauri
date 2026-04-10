use base64::Engine;
use dom_query::Document;
use serde_json::json;
use sha2::{Digest, Sha256};
use std::collections::BTreeMap;
use std::path::{Path, PathBuf};
use walkdir::WalkDir;

const SCRIPT_NONCE_TOKEN: &str = "__TAURI_SCRIPT_NONCE__";
const STYLE_NONCE_TOKEN: &str = "__TAURI_STYLE_NONCE__";

fn normalize_script_for_csp(input: &[u8]) -> Vec<u8> {
    let mut output = Vec::with_capacity(input.len());
    let mut i = 0;
    while i < input.len() {
        match input[i] {
            b'\r' => {
                if i + 1 < input.len() && input[i + 1] == b'\n' {
                    output.push(b'\n');
                    i += 2;
                } else {
                    output.push(b'\n');
                    i += 1;
                }
            }
            _ => {
                output.push(input[i]);
                i += 1;
            }
        }
    }
    output
}

fn hash_script(bytes: &[u8]) -> String {
    let hash = Sha256::digest(normalize_script_for_csp(bytes));
    format!(
        "'sha256-{}'",
        base64::engine::general_purpose::STANDARD.encode(hash)
    )
}

fn parse_doc(html: String) -> Document {
    Document::from(html)
}

fn serialize_doc(document: &Document) -> Vec<u8> {
    document.html().as_bytes().to_vec()
}

fn inject_nonce(document: &Document, selector: &str, token: &str) {
    for element in document.select(selector).nodes() {
        if element.attr("nonce").is_none() {
            element.set_attr("nonce", token);
        }
    }
}

fn inject_nonce_token(document: &Document) {
    inject_nonce(document, "script[src^='http']", SCRIPT_NONCE_TOKEN);
    inject_nonce(document, "style", STYLE_NONCE_TOKEN);
}

fn asset_key(root: &Path, path: &Path) -> String {
    let relative = path.strip_prefix(root).unwrap();
    let parts = relative
        .components()
        .map(|component| component.as_os_str().to_string_lossy().into_owned())
        .collect::<Vec<_>>();
    format!("/{}", parts.join("/"))
}

fn main() {
    let mut args = std::env::args().skip(1);
    let input_dir = PathBuf::from(args.next().expect("missing input dir"));
    let output_file = PathBuf::from(args.next().expect("missing output file"));
    assert!(args.next().is_none(), "expected arguments: <input_dir> <output_file>");

    let mut assets = BTreeMap::<String, String>::new();
    let mut global_script_hashes = Vec::<String>::new();
    let mut html_inline_hashes = BTreeMap::<String, Vec<String>>::new();

    let mut paths = WalkDir::new(&input_dir)
        .follow_links(true)
        .into_iter()
        .filter_map(Result::ok)
        .filter(|entry| entry.file_type().is_file())
        .map(|entry| entry.into_path())
        .collect::<Vec<_>>();
    paths.sort();

    for path in paths {
        let key = asset_key(&input_dir, &path);
        let mut input = std::fs::read(&path)
            .unwrap_or_else(|error| panic!("failed to read {}: {error}", path.display()));

        match path.extension().and_then(|ext| ext.to_str()) {
            Some("js") | Some("mjs") => {
                global_script_hashes.push(hash_script(&input));
            }
            Some("html") => {
                let document = parse_doc(String::from_utf8_lossy(&input).into_owned());
                inject_nonce_token(&document);
                let hashes = document
                    .select("script:not(:empty)")
                    .iter()
                    .map(|element| hash_script(element.text().as_bytes()))
                    .collect::<Vec<_>>();
                if !hashes.is_empty() {
                    html_inline_hashes.insert(key.clone(), hashes);
                }
                input = serialize_doc(&document);
            }
            _ => {}
        }

        assets.insert(key, String::from_utf8_lossy(&input).into_owned());
    }

    let output = json!({
        "assets": assets,
        "global_script_hashes": global_script_hashes,
        "html_inline_hashes": html_inline_hashes,
    });
    if let Some(parent) = output_file.parent() {
        std::fs::create_dir_all(parent).unwrap_or_else(|error| {
            panic!("failed to create {}: {error}", parent.display())
        });
    }
    std::fs::write(&output_file, serde_json::to_vec_pretty(&output).unwrap())
        .unwrap_or_else(|error| panic!("failed to write {}: {error}", output_file.display()));
}
