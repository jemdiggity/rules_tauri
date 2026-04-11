use anyhow::{bail, Context, Result};
use quote::quote;
use std::ffi::OsString;
use std::fs;
use std::path::{Path, PathBuf};
use syn::{Expr, ExprArray, ExprReference, File, Item};

const ACL_MANIFESTS_FILE_NAME: &str = "acl-manifests.json";
const CAPABILITIES_FILE_NAME: &str = "capabilities.json";

#[cfg(all(target_arch = "aarch64", target_os = "macos"))]
const TARGET_TRIPLE: &str = "aarch64-apple-darwin";
#[cfg(all(target_arch = "x86_64", target_os = "macos"))]
const TARGET_TRIPLE: &str = "x86_64-apple-darwin";
#[cfg(not(any(
    all(target_arch = "aarch64", target_os = "macos"),
    all(target_arch = "x86_64", target_os = "macos"),
)))]
compile_error!("tauri_context_codegen only supports macOS x86_64 and aarch64 exec targets");

struct Args {
    config: PathBuf,
    embedded_assets_rust: PathBuf,
    acl_out_dir: PathBuf,
    out: PathBuf,
}

fn main() -> Result<()> {
    let args = parse_args()?;

    let invocation_dir = std::env::current_dir().context("failed to determine current directory")?;
    let config = absolutize(&invocation_dir, args.config);
    let embedded_assets_rust = absolutize(&invocation_dir, args.embedded_assets_rust);
    let acl_out_dir = absolutize(&invocation_dir, args.acl_out_dir);
    let out = absolutize(&invocation_dir, args.out);
    let out_dir = out
        .parent()
        .context("`--out` must include a parent directory")?
        .to_path_buf();

    fs::create_dir_all(&out_dir)
        .with_context(|| format!("failed to create output dir {}", out_dir.display()))?;
    copy_acl_outputs(&acl_out_dir, &out_dir)?;

    std::env::set_var("OUT_DIR", &out_dir);
    std::env::set_var("TAURI_ENV_TARGET_TRIPLE", TARGET_TRIPLE);

    let (mut config_value, config_parent) =
        tauri_codegen::get_config(&config).with_context(|| format!("failed to read {}", config.display()))?;
    config_value.build.dev_url = None;

    let embedded_assets = parse_embedded_assets_expr(&embedded_assets_rust)?;
    let context = tauri_codegen::context_codegen(tauri_codegen::ContextData {
        dev: true,
        config: config_value,
        config_parent,
        root: quote!(::tauri),
        capabilities: None,
        assets: Some(embedded_assets),
        test: false,
    })
    .context("failed to generate Tauri build context")?;

    fs::write(&out, format!("{context}\n"))
        .with_context(|| format!("failed to write {}", out.display()))?;
    Ok(())
}

fn parse_args() -> Result<Args> {
    let mut config = None;
    let mut embedded_assets_rust = None;
    let mut acl_out_dir = None;
    let mut out = None;
    let mut args = std::env::args_os();
    let _program = args.next();

    while let Some(flag) = args.next() {
        match flag.to_str() {
            Some("--config") => config = Some(next_path("--config", &mut args)?),
            Some("--embedded-assets-rust") => {
                embedded_assets_rust = Some(next_path("--embedded-assets-rust", &mut args)?)
            }
            Some("--acl-out-dir") => acl_out_dir = Some(next_path("--acl-out-dir", &mut args)?),
            Some("--out") => out = Some(next_path("--out", &mut args)?),
            Some(other) => bail!("unknown argument `{other}`"),
            None => bail!("non-utf8 argument is not supported"),
        }
    }

    Ok(Args {
        config: config.context("missing required `--config`")?,
        embedded_assets_rust: embedded_assets_rust
            .context("missing required `--embedded-assets-rust`")?,
        acl_out_dir: acl_out_dir.context("missing required `--acl-out-dir`")?,
        out: out.context("missing required `--out`")?,
    })
}

fn next_path(flag: &str, args: &mut impl Iterator<Item = OsString>) -> Result<PathBuf> {
    let value = args
        .next()
        .with_context(|| format!("missing value for `{flag}`"))?;
    Ok(PathBuf::from(value))
}

fn absolutize(cwd: &Path, path: PathBuf) -> PathBuf {
    if path.is_absolute() {
        path
    } else {
        cwd.join(path)
    }
}

fn copy_acl_outputs(source_dir: &Path, out_dir: &Path) -> Result<()> {
    for name in [ACL_MANIFESTS_FILE_NAME, CAPABILITIES_FILE_NAME] {
        let source = source_dir.join(name);
        let destination = out_dir.join(name);
        fs::copy(&source, &destination).with_context(|| {
            format!(
                "failed to copy {} to {}",
                source.display(),
                destination.display()
            )
        })?;
    }
    Ok(())
}

fn parse_embedded_assets_expr(path: &Path) -> Result<Expr> {
    let source_bytes = fs::read(path)
        .with_context(|| format!("failed to read {}", path.display()))?;
    let source = String::from_utf8(source_bytes.clone())
        .with_context(|| format!("failed to decode {}", path.display()))?;
    let file = syn::parse_file(&source)
        .with_context(|| format!("failed to parse {}", path.display()))?;
    let marker = format!(
        "RULES_TAURI_BAZEL_OWNED_EMBEDDED_ASSETS:{:016x}",
        fnv1a64(&source_bytes)
    );

    let embedded_assets = const_array(&file, "EMBEDDED_ASSETS")?;
    let global_hashes = const_array(&file, "GLOBAL_CSP_HASHES")?;
    let html_hashes = const_array(&file, "HTML_CSP_HASHES")?;

    let asset_entries = embedded_assets
        .elems
        .iter()
        .map(asset_entry_tokens)
        .collect::<Result<Vec<_>>>()?;
    let global_hash_tokens = global_hashes
        .elems
        .iter()
        .map(hash_entry_tokens)
        .collect::<Result<Vec<_>>>()?;
    let html_hash_tokens = html_hashes
        .elems
        .iter()
        .map(html_hash_entry_tokens)
        .collect::<Result<Vec<_>>>()?;

    syn::parse2::<Expr>(quote!({
        #[allow(unused_imports)]
        use ::tauri::utils::assets::{CspHash, EmbeddedAssets, phf, phf::phf_map};
        const _: &str = #marker;
        EmbeddedAssets::new(
            phf_map! {
                #(#asset_entries,)*
            },
            &[
                #(#global_hash_tokens,)*
            ],
            phf_map! {
                #(#html_hash_tokens,)*
            },
        )
    }))
    .context("failed to build embedded assets expression")
}

fn fnv1a64(data: &[u8]) -> u64 {
    let mut value = 0xCBF29CE484222325u64;
    for byte in data {
        value ^= u64::from(*byte);
        value = value.wrapping_mul(0x100000001B3);
    }
    value
}

fn const_array(file: &File, const_name: &str) -> Result<ExprArray> {
    let item = file
        .items
        .iter()
        .find_map(|item| match item {
            Item::Const(item_const) if item_const.ident == const_name => Some(item_const),
            _ => None,
        })
        .with_context(|| format!("failed to find `{const_name}`"))?;

    match item.expr.as_ref() {
        Expr::Reference(ExprReference { expr, .. }) => match expr.as_ref() {
            Expr::Array(array) => Ok(array.clone()),
            _ => bail!("`{const_name}` must be a referenced array"),
        },
        _ => bail!("`{const_name}` must be a referenced array"),
    }
}

fn tuple_elements(expr: &Expr, count: usize) -> Result<Vec<Expr>> {
    let Expr::Tuple(tuple) = expr else {
        bail!("expected tuple expression");
    };
    if tuple.elems.len() != count {
        bail!("expected tuple with {count} elements, got {}", tuple.elems.len());
    }
    Ok(tuple.elems.iter().cloned().collect())
}

fn string_literal(expr: &Expr) -> Result<syn::LitStr> {
    let Expr::Lit(expr_lit) = expr else {
        bail!("expected string literal");
    };
    let syn::Lit::Str(value) = &expr_lit.lit else {
        bail!("expected string literal");
    };
    Ok(value.clone())
}

fn array_from_reference(expr: &Expr) -> Result<ExprArray> {
    match expr {
        Expr::Reference(ExprReference { expr, .. }) => match expr.as_ref() {
            Expr::Array(array) => Ok(array.clone()),
            _ => bail!("expected referenced array"),
        },
        _ => bail!("expected referenced array"),
    }
}

fn asset_entry_tokens(expr: &Expr) -> Result<proc_macro2::TokenStream> {
    let elements = tuple_elements(expr, 2)?;
    let key = &elements[0];
    let value = &elements[1];
    Ok(quote!(#key => #value))
}

fn hash_entry_tokens(expr: &Expr) -> Result<proc_macro2::TokenStream> {
    let elements = tuple_elements(expr, 2)?;
    let kind = string_literal(&elements[0])?.value();
    let value = &elements[1];
    match kind.as_str() {
        "script" => Ok(quote!(::tauri::utils::assets::CspHash::Script(#value))),
        "style" => Ok(quote!(::tauri::utils::assets::CspHash::Style(#value))),
        _ => bail!("unsupported CSP hash kind `{kind}`"),
    }
}

fn html_hash_entry_tokens(expr: &Expr) -> Result<proc_macro2::TokenStream> {
    let elements = tuple_elements(expr, 2)?;
    let key = &elements[0];
    let hashes = array_from_reference(&elements[1])?;
    let hash_tokens = hashes
        .elems
        .iter()
        .map(hash_entry_tokens)
        .collect::<Result<Vec<_>>>()?;
    Ok(quote!(
        #key => &[
            #(#hash_tokens,)*
        ]
    ) as proc_macro2::TokenStream)
}
