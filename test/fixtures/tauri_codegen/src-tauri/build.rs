use quote::quote;
use std::path::{Path, PathBuf};

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
    println!("cargo:rerun-if-env-changed=RULES_TAURI_BAZEL_EMBEDDED_ASSETS");

    let attributes = tauri_build::Attributes::new().codegen(tauri_build::CodegenContext::new());
    tauri_build::try_build(attributes).expect("failed to generate Tauri build context");

    if let Ok(embedded_assets_path) = std::env::var("RULES_TAURI_BAZEL_EMBEDDED_ASSETS") {
        println!("cargo:rerun-if-changed={embedded_assets_path}");
        patch_codegen_context(Path::new(&embedded_assets_path));
    }
}

fn patch_codegen_context(embedded_assets_path: &Path) {
    let context_path = PathBuf::from(std::env::var("OUT_DIR").expect("missing OUT_DIR"))
        .join("tauri-build-context.rs");
    let context_source = std::fs::read_to_string(&context_path)
        .unwrap_or_else(|error| panic!("failed to read {}: {error}", context_path.display()));
    let mut context_expr: syn::Expr = syn::parse_str(&context_source).unwrap_or_else(|error| {
        panic!(
            "failed to parse generated Tauri context {}: {error}",
            context_path.display()
        )
    });
    let replacement = render_embedded_assets_expr(embedded_assets_path);
    replace_inner_assets_expr(&mut context_expr, replacement);

    std::fs::write(&context_path, format!("{}\n", quote!(#context_expr)))
        .unwrap_or_else(|error| panic!("failed to write {}: {error}", context_path.display()));
}

fn render_embedded_assets_expr(embedded_assets_path: &Path) -> syn::Expr {
    let embedded_assets_source = std::fs::read_to_string(embedded_assets_path)
        .unwrap_or_else(|error| panic!("failed to read {}: {error}", embedded_assets_path.display()));
    let embedded_assets_hash = fnv1a64(embedded_assets_source.as_bytes());
    let syntax = syn::parse_file(&embedded_assets_source).unwrap_or_else(|error| {
        panic!(
            "failed to parse generated embedded assets {}: {error}",
            embedded_assets_path.display()
        )
    });
    let entries = extract_embedded_assets_entries(&syntax, embedded_assets_path);

    let mut map_entries = proc_macro2::TokenStream::new();
    for (key, value) in entries {
        map_entries.extend(quote!(#key => #value,));
    }
    let marker = format!("RULES_TAURI_BAZEL_OWNED_EMBEDDED_ASSETS:{embedded_assets_hash:016x}");

    syn::parse2(quote!({
        #[allow(unused_imports)]
        use ::tauri::utils::assets::{CspHash, EmbeddedAssets, phf, phf::phf_map};
        const _: &str = #marker;
        EmbeddedAssets::new(
            phf_map! { #map_entries },
            &[],
            phf_map! {},
        )
    }))
    .expect("failed to build Bazel-owned embedded assets expression")
}

fn extract_embedded_assets_entries(
    file: &syn::File,
    embedded_assets_path: &Path,
) -> Vec<(syn::LitStr, syn::LitByteStr)> {
    let mut entries = Vec::new();
    for item in &file.items {
        let syn::Item::Const(item_const) = item else {
            continue;
        };
        if item_const.ident != "EMBEDDED_ASSETS" {
            continue;
        }

        let syn::Expr::Reference(array_ref) = &*item_const.expr else {
            panic!("EMBEDDED_ASSETS must be a reference to an array");
        };
        let syn::Expr::Array(array) = &*array_ref.expr else {
            panic!("EMBEDDED_ASSETS must reference an array literal");
        };

        for element in &array.elems {
            let syn::Expr::Tuple(tuple) = element else {
                panic!("embedded assets entry must be a tuple");
            };
            assert!(
                tuple.elems.len() == 2,
                "embedded assets entry must contain exactly 2 elements"
            );

            let key = match &tuple.elems[0] {
                syn::Expr::Lit(expr) => match &expr.lit {
                    syn::Lit::Str(value) => value.clone(),
                    _ => panic!("embedded assets key must be a string literal"),
                },
                _ => panic!("embedded assets key must be a literal expression"),
            };
            let value = match &tuple.elems[1] {
                syn::Expr::Lit(expr) => match &expr.lit {
                    syn::Lit::ByteStr(value) => value.clone(),
                    _ => panic!("embedded assets value must be a byte string literal"),
                },
                _ => panic!("embedded assets value must be a literal expression"),
            };
            entries.push((key, value));
        }

        return entries;
    }

    panic!(
        "failed to find EMBEDDED_ASSETS in {}",
        embedded_assets_path_display(embedded_assets_path)
    );
}

fn embedded_assets_path_display(path: &Path) -> String {
    path.display().to_string()
}

fn fnv1a64(bytes: &[u8]) -> u64 {
    let mut hash = 0xcbf29ce484222325_u64;
    for byte in bytes {
        hash ^= u64::from(*byte);
        hash = hash.wrapping_mul(0x100000001b3);
    }
    hash
}

fn replace_inner_assets_expr(context_expr: &mut syn::Expr, replacement: syn::Expr) {
    let syn::Expr::Block(outer_block) = context_expr else {
        panic!("generated Tauri context must be a block expression");
    };
    let last_stmt = outer_block
        .block
        .stmts
        .last_mut()
        .expect("generated Tauri context is missing the final inner(...) call");
    let call = match last_stmt {
        syn::Stmt::Expr(expr, _) => match expr {
            syn::Expr::Call(call) => call,
            _ => panic!("generated Tauri context final statement must be a call expression"),
        },
        _ => panic!("generated Tauri context final statement must be an expression"),
    };
    let syn::Expr::Path(path) = &*call.func else {
        panic!("generated Tauri context final call must target inner");
    };
    assert!(
        path.path
            .segments
            .last()
            .is_some_and(|segment| segment.ident == "inner"),
        "generated Tauri context final call must target inner"
    );
    assert!(
        call.args.len() == 1,
        "generated Tauri context final inner call must take exactly one argument"
    );
    call.args[0] = replacement;
}
