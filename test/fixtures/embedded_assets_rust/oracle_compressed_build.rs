fn rust_string_literal(text: &str) -> String {
    let mut output = String::from("\"");
    for ch in text.chars() {
        match ch {
            '\\' => output.push_str("\\\\"),
            '"' => output.push_str("\\\""),
            '\n' => output.push_str("\\n"),
            '\r' => output.push_str("\\r"),
            '\t' => output.push_str("\\t"),
            '\0' => output.push_str("\\0"),
            ch if ch.is_ascii_graphic() || ch == ' ' => output.push(ch),
            ch => {
                use std::fmt::Write as _;
                write!(output, "\\u{{{:x}}}", ch as u32).expect("failed to write string escape");
            }
        }
    }
    output.push('"');
    output
}

fn rust_byte_string_literal(bytes: &[u8]) -> String {
    let mut output = String::from("b\"");
    for byte in bytes {
        match byte {
            b'\\' => output.push_str("\\\\"),
            b'"' => output.push_str("\\\""),
            b'\n' => output.push_str("\\n"),
            b'\r' => output.push_str("\\r"),
            b'\t' => output.push_str("\\t"),
            b'\0' => output.push_str("\\0"),
            0x20..=0x7e => output.push(*byte as char),
            byte => {
                use std::fmt::Write as _;
                write!(output, "\\x{:02x}", byte).expect("failed to write byte escape");
            }
        }
    }
    output.push('"');
    output
}

fn main() {
    use quote::ToTokens as _;

    let manifest_dir =
        std::env::var("CARGO_MANIFEST_DIR").expect("CARGO_MANIFEST_DIR must be set by cargo");
    let assets_dir = std::path::Path::new(&manifest_dir).join("assets");
    let stable_file = std::path::Path::new(&manifest_dir).join("embedded_assets_compressed.oracle.rs");

    println!("cargo:rerun-if-changed=assets");
    println!("cargo:rerun-if-changed=assets/index.html");
    println!("cargo:rerun-if-changed=assets/assets/app.css");
    println!("cargo:rerun-if-changed=assets/assets/app.js");

    let embedded = tauri_codegen::embedded_assets::EmbeddedAssets::new(
        assets_dir,
        &tauri_codegen::embedded_assets::AssetOptions::new(
            tauri_utils::config::PatternKind::Brownfield,
        ),
        |_key, _path, _input, _csp_hashes| {
            Ok::<(), tauri_codegen::embedded_assets::EmbeddedAssetsError>(())
        },
    )
    .expect("failed to generate embedded assets for the compression oracle");

    let tokens = embedded.to_token_stream().to_string();
    let pair_re = regex::Regex::new(
        "\"(?P<key>(?:\\\\.|[^\"])*)\"\\s*=>\\s*\\{.*?include_bytes\\s*!\\s*\\(\\s*\"(?:\\\\.|[^\"])*\"\\s*\\)\\s*;\\s*include_bytes\\s*!\\s*\\(\\s*\"(?P<path>(?:\\\\.|[^\"])*)\"\\s*\\).*?\\}",
    )
    .expect("failed to compile pair regex");

    let mut pairs = std::collections::BTreeMap::<String, Vec<u8>>::new();
    for captures in pair_re.captures_iter(&tokens) {
        let key_token = format!("\"{}\"", &captures["key"]);
        let key = unescape_string(&key_token);
        let path_token = format!("\"{}\"", &captures["path"]);
        let path = std::path::PathBuf::from(unescape_string(&path_token));
        let bytes = std::fs::read(&path)
            .unwrap_or_else(|error| panic!("failed to read compressed oracle asset {path:?}: {error}"));
        pairs.insert(key, bytes);
    }
    assert!(
        !pairs.is_empty(),
        "failed to parse any compressed embedded assets from oracle token stream: {tokens}"
    );

    let mut source = String::new();
    source.push_str("// @generated compression oracle\n");
    source.push_str("// DO NOT EDIT.\n\n");
    source.push_str("pub const EMBEDDED_ASSETS: &[(&str, &[u8])] = &[\n");
    for (key, bytes) in pairs {
        source.push_str("    (");
        source.push_str(&rust_string_literal(&key));
        source.push_str(", ");
        source.push_str(&rust_byte_string_literal(&bytes));
        source.push_str("),\n");
    }
    source.push_str("];\n");
    std::fs::write(&stable_file, source).unwrap_or_else(|error| {
        panic!("failed to write compressed embedded assets oracle output {stable_file:?}: {error}");
    });
}

fn unescape_string(token: &str) -> String {
    assert!(token.starts_with('"') && token.ends_with('"'));
    let mut i = 1;
    let bytes = token.as_bytes();
    let mut result = String::new();
    while i < bytes.len() - 1 {
        if bytes[i] != b'\\' {
            result.push(bytes[i] as char);
            i += 1;
            continue;
        }
        i += 1;
        match bytes[i] {
            b'\\' => {
                result.push('\\');
                i += 1;
            }
            b'"' => {
                result.push('"');
                i += 1;
            }
            b'n' => {
                result.push('\n');
                i += 1;
            }
            b'r' => {
                result.push('\r');
                i += 1;
            }
            b't' => {
                result.push('\t');
                i += 1;
            }
            b'0' => {
                result.push('\0');
                i += 1;
            }
            b'u' => {
                assert_eq!(bytes[i + 1], b'{');
                let mut end = i + 2;
                while bytes[end] != b'}' {
                    end += 1;
                }
                let codepoint =
                    u32::from_str_radix(std::str::from_utf8(&bytes[i + 2..end]).unwrap(), 16)
                        .expect("failed to decode unicode escape");
                result.push(char::from_u32(codepoint).expect("invalid unicode escape"));
                i = end + 1;
            }
            other => panic!("unsupported string escape: {}", other as char),
        }
    }
    result
}
