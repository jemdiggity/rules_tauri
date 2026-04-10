mod build_contract;

use quote::quote;
use std::path::PathBuf;
use syn::visit_mut::{self, VisitMut};

fn main() {
    if let Ok(manifest_dir) = std::env::var("CARGO_MANIFEST_DIR") {
        std::env::set_current_dir(&manifest_dir)
            .unwrap_or_else(|error| panic!("failed to chdir to {manifest_dir}: {error}"));
    }

    if let Ok(frontend_dist) = std::env::var("RULES_TAURI_FRONTEND_DIST") {
        let config_patch = serde_json::json!({
            "build": {
                "devUrl": serde_json::Value::Null,
                "frontendDist": frontend_dist,
            },
        });
        std::env::set_var("TAURI_CONFIG", config_patch.to_string());
    }
    println!("cargo:rerun-if-env-changed=RULES_TAURI_FRONTEND_DIST");

    let attributes = tauri_build::Attributes::new().codegen(tauri_build::CodegenContext::new());
    tauri_build::try_build(attributes).expect("failed to generate Tauri build context");
    normalize_build_config_paths();
}

fn normalize_build_config_paths() {
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
    let mut patcher = GeneratedContextPathPatcher {
        frontend_dist: syn::LitStr::new("../dist", proc_macro2::Span::call_site()),
    };
    patcher.visit_expr_mut(&mut context_expr);

    std::fs::write(&context_path, format!("{}\n", quote!(#context_expr)))
        .unwrap_or_else(|error| panic!("failed to write {}: {error}", context_path.display()));
}

struct GeneratedContextPathPatcher {
    frontend_dist: syn::LitStr,
}

impl VisitMut for GeneratedContextPathPatcher {
    fn visit_expr_struct_mut(&mut self, node: &mut syn::ExprStruct) {
        visit_mut::visit_expr_struct_mut(self, node);

        let Some(last_segment) = node.path.segments.last() else {
            return;
        };
        if last_segment.ident != "BuildConfig" {
            return;
        }

        for field in &mut node.fields {
            let syn::Member::Named(member) = &field.member else {
                continue;
            };
            if member == "frontend_dist" {
                let frontend_dist = &self.frontend_dist;
                field.expr = syn::parse_quote!(
                    :: core :: option :: Option :: Some(
                        :: tauri :: utils :: config :: FrontendDist :: Directory(
                            :: std :: path :: PathBuf :: from(#frontend_dist)
                        )
                    )
                );
            }
        }
    }
}
