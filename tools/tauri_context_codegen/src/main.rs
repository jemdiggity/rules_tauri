use anyhow::{bail, Context, Result};
use blake3;
use plist;
use quote::{quote, TokenStreamExt};
use std::ffi::{OsStr, OsString};
use std::fmt::Write;
use std::fs;
use std::io::Cursor;
use std::path::{Path, PathBuf};
use std::str::FromStr;
use syn::{Expr, ExprArray, ExprReference, File, Item};
use tauri_utils::{
    acl::{
        get_capabilities, manifest::Manifest, resolved::Resolved,
    },
    config::{Config, PatternKind},
    platform::Target,
    tokens::{map_lit, str_lit},
    write_if_changed,
};

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

    let invocation_dir =
        std::env::current_dir().context("failed to determine current directory")?;
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

    let config_parent = config
        .parent()
        .context("`--config` must include a parent directory")?
        .to_path_buf();
    let mut config_value = load_config(&config, TARGET_TRIPLE)?;
    config_value.build.dev_url = None;

    let embedded_assets = parse_embedded_assets_expr(&embedded_assets_rust)?;
    let context = generate_context(&config_value, &config_parent, embedded_assets, &acl_out_dir)
        .context("failed to generate repo-owned Tauri build context")?;

    fs::write(&out, format!("{context}\n"))
        .with_context(|| format!("failed to write {}", out.display()))?;
    Ok(())
}

fn load_config(config_path: &Path, target_triple: &str) -> Result<tauri_utils::config::Config> {
    let target = tauri_utils::platform::Target::from_triple(target_triple);
    let config_value = if uses_default_config_layout(config_path) {
        let config_parent = config_path
            .parent()
            .context("config path must have parent")?;
        tauri_utils::config::parse::read_from(target, config_parent)
            .with_context(|| format!("failed to parse config under {}", config_parent.display()))?
            .0
    } else {
        tauri_utils::config::parse::parse_value(target, config_path)
            .with_context(|| format!("failed to parse {}", config_path.display()))?
            .0
    };
    serde_json::from_value(config_value).context("failed to decode normalized Tauri config")
}

fn uses_default_config_layout(config_path: &Path) -> bool {
    matches!(
        config_path.file_name(),
        Some(name) if name == OsStr::new("tauri.conf.json")
    )
}

fn generate_context(
    config: &Config,
    config_parent: &Path,
    embedded_assets: Expr,
    _acl_out_dir: &Path,
) -> Result<String> {
    let target = std::env::var("TAURI_ENV_TARGET_TRIPLE")
        .as_deref()
        .map(Target::from_triple)
        .unwrap_or_else(|_| Target::current());

    let default_window_icon = cached_window_icon_expr(config, config_parent, target)?;
    let app_icon = cached_app_icon_expr(config, config_parent, target)?;
    let package_info = package_info_expr(config)?;
    let maybe_embed_plist_block = maybe_embed_plist_block(config, config_parent, target)?;
    let pattern = pattern_expr(config, config_parent)?;
    let runtime_authority = runtime_authority_expr(config, target)?;
    let plugin_global_api_scripts = plugin_global_api_scripts_expr(config, config_parent)?;
    let maybe_config_parent_setter = maybe_config_parent_setter(config_parent);

    let embedded_assets_expr = quote!(#embedded_assets);

    let context = quote!({
        #maybe_embed_plist_block

        #[allow(unused_mut, clippy::let_and_return)]
        let mut context = ::tauri::Context::new(
            #config,
            ::std::boxed::Box::new(assets),
            #default_window_icon,
            #app_icon,
            #package_info,
            #pattern,
            #runtime_authority,
            #plugin_global_api_scripts
        );

        #maybe_config_parent_setter

        context
    });

    let output = quote!({
        fn inner<R: ::tauri::Runtime, A: ::tauri::Assets<R> + 'static>(assets: A) -> ::tauri::Context<R> {
            let thread = ::std::thread::Builder::new()
                .name(String::from("generated tauri context creation"))
                .stack_size(8 * 1024 * 1024)
                .spawn(move || #context)
                .expect("unable to create thread with 8MiB stack");

            match thread.join() {
                Ok(context) => context,
                Err(_) => {
                    eprintln!("the generated Tauri `Context` panicked during creation");
                    ::std::process::exit(101);
                }
            }
        }
        inner(#embedded_assets_expr)
    });

    Ok(output.to_string())
}

fn maybe_config_parent_setter(config_parent: &Path) -> proc_macro2::TokenStream {
    let config_parent = config_parent.to_string_lossy();
    quote!({
        context.with_config_parent(#config_parent);
    })
}

fn maybe_embed_plist_block(
    config: &Config,
    config_parent: &Path,
    target: Target,
) -> Result<proc_macro2::TokenStream> {
    #[cfg(target_os = "macos")]
    {
        let running_tests = false;
        if target == Target::MacOS && !running_tests {
            let info_plist_path = config_parent.join("Info.plist");
            let mut info_plist = if info_plist_path.exists() {
                plist::Value::from_file(&info_plist_path).unwrap_or_else(|e| {
                    panic!("failed to read plist {}: {}", info_plist_path.display(), e)
                })
            } else {
                plist::Value::Dictionary(Default::default())
            };

            if let Some(plist) = info_plist.as_dictionary_mut() {
                if let Some(bundle_name) = config
                    .bundle
                    .macos
                    .bundle_name
                    .as_ref()
                    .or(config.product_name.as_ref())
                {
                    plist.insert("CFBundleName".into(), bundle_name.as_str().into());
                }

                if let Some(version) = &config.version {
                    let bundle_version = &config.bundle.macos.bundle_version;
                    plist.insert("CFBundleShortVersionString".into(), version.clone().into());
                    plist.insert(
                        "CFBundleVersion".into(),
                        bundle_version
                            .clone()
                            .unwrap_or_else(|| version.clone())
                            .into(),
                    );
                }
            }

            let mut plist_contents = std::io::BufWriter::new(Vec::new());
            info_plist
                .to_writer_xml(&mut plist_contents)
                .expect("failed to serialize plist");
            let plist_contents =
                String::from_utf8_lossy(&plist_contents.into_inner().unwrap()).into_owned();

            let plist = Cached::try_from(plist_contents)?;
            return Ok(quote!({
                tauri::embed_plist::embed_info_plist!(#plist);
            }));
        }
    }

    Ok(quote!())
}

fn package_info_expr(config: &Config) -> Result<proc_macro2::TokenStream> {
    let package_name = if let Some(product_name) = &config.product_name {
        quote!(#product_name.to_string())
    } else {
        quote!(env!("CARGO_PKG_NAME").to_string())
    };
    let package_version = if let Some(version) = &config.version {
        semver::Version::from_str(version)?;
        quote!(#version.to_string())
    } else {
        quote!(env!("CARGO_PKG_VERSION").to_string())
    };
    Ok(quote!(
        ::tauri::PackageInfo {
            name: #package_name,
            version: #package_version.parse().unwrap(),
            authors: env!("CARGO_PKG_AUTHORS"),
            description: env!("CARGO_PKG_DESCRIPTION"),
            crate_name: env!("CARGO_PKG_NAME"),
        }
    ))
}

fn pattern_expr(config: &Config, _config_parent: &Path) -> Result<proc_macro2::TokenStream> {
    let pattern = match &config.app.security.pattern {
        PatternKind::Brownfield => quote!(::tauri::Pattern::Brownfield),
        #[cfg(not(feature = "isolation"))]
        PatternKind::Isolation { dir: _ } => quote!(::tauri::Pattern::Brownfield),
        #[cfg(feature = "isolation")]
        PatternKind::Isolation { dir } => {
            let dir = config_parent.join(dir);
            if !dir.exists() {
                panic!("The isolation application path is set to `{dir:?}` but it does not exist")
            }
            unimplemented!("isolation pattern is not used in this fixture")
        }
    };
    Ok(pattern)
}

fn runtime_authority_expr(config: &Config, target: Target) -> Result<proc_macro2::TokenStream> {
    let acl_file_path = std::env::var("OUT_DIR")
        .map(PathBuf::from)
        .context("missing OUT_DIR")?
        .join(ACL_MANIFESTS_FILE_NAME);
    let acl: std::collections::BTreeMap<String, Manifest> = if acl_file_path.exists() {
        let acl_file =
            std::fs::read_to_string(&acl_file_path).expect("failed to read plugin manifest map");
        serde_json::from_str(&acl_file).expect("failed to parse plugin manifest map")
    } else {
        Default::default()
    };

    let capabilities_file_path = std::env::var("OUT_DIR")
        .map(PathBuf::from)
        .context("missing OUT_DIR")?
        .join(CAPABILITIES_FILE_NAME);
    let capabilities_from_files = if capabilities_file_path.exists() {
        let capabilities_json =
            std::fs::read_to_string(&capabilities_file_path).expect("failed to read capabilities");
        serde_json::from_str(&capabilities_json).expect("failed to parse capabilities")
    } else {
        Default::default()
    };
    let capabilities = get_capabilities(config, capabilities_from_files, None).unwrap();

    let resolved = Resolved::resolve(&acl, capabilities, target).expect("failed to resolve ACL");
    let acl_tokens = map_lit(
        quote! { ::std::collections::BTreeMap },
        &acl,
        str_lit,
        std::convert::identity,
    );

    Ok(quote!(::tauri::runtime_authority!(#acl_tokens, #resolved)))
}

fn plugin_global_api_scripts_expr(
    config: &Config,
    config_parent: &Path,
) -> Result<proc_macro2::TokenStream> {
    if config.app.with_global_tauri {
        if let Some(scripts) = tauri_utils::plugin::read_global_api_scripts(
            &PathBuf::from(std::env::var("OUT_DIR").context("missing OUT_DIR")?),
        ) {
            let scripts = scripts.into_iter().map(|s| quote!(#s));
            return Ok(quote!(::std::option::Option::Some(&[#(#scripts),*])));
        }
    }
    let _ = config_parent;
    Ok(quote!(::std::option::Option::None))
}

fn cached_window_icon_expr(
    config: &Config,
    config_parent: &Path,
    target: Target,
) -> Result<proc_macro2::TokenStream> {
    if target == Target::Windows {
        let icon_path = find_icon(config, config_parent, |i| i.ends_with(".ico"), "icons/icon.ico");
        if icon_path.exists() {
            let icon = CachedIcon::new(&quote!(::tauri), &icon_path)?;
            return Ok(quote!(::std::option::Option::Some(#icon)));
        }

        let icon_path = find_icon(config, config_parent, |i| i.ends_with(".png"), "icons/icon.png");
        let icon = CachedIcon::new(&quote!(::tauri), &icon_path)?;
        return Ok(quote!(::std::option::Option::Some(#icon)));
    }

    let icon_path = find_icon(config, config_parent, |i| i.ends_with(".png"), "icons/icon.png");
    let icon = CachedIcon::new(&quote!(::tauri), &icon_path)?;
    Ok(quote!(::std::option::Option::Some(#icon)))
}

fn cached_app_icon_expr(
    config: &Config,
    config_parent: &Path,
    target: Target,
) -> Result<proc_macro2::TokenStream> {
    if target == Target::MacOS {
        let mut icon_path = find_icon(config, config_parent, |i| i.ends_with(".icns"), "icons/icon.png");
        if !icon_path.exists() {
            icon_path = find_icon(config, config_parent, |i| i.ends_with(".png"), "icons/icon.png");
        }
        let icon = CachedIcon::new_raw(&quote!(::tauri), &icon_path)?;
        return Ok(quote!(::std::option::Option::Some(#icon.to_vec())));
    }

    Ok(quote!(::std::option::Option::None))
}

fn find_icon(
    config: &Config,
    config_parent: &Path,
    predicate: impl Fn(&&String) -> bool,
    default: &str,
) -> PathBuf {
    let icon_path = config
        .bundle
        .icon
        .iter()
        .find(predicate)
        .map(AsRef::as_ref)
        .unwrap_or(default);
    config_parent.join(icon_path)
}

struct Cached {
    checksum: String,
}

impl TryFrom<String> for Cached {
    type Error = anyhow::Error;

    fn try_from(value: String) -> Result<Self> {
        Self::try_from(value.into_bytes())
    }
}

impl TryFrom<Vec<u8>> for Cached {
    type Error = anyhow::Error;

    fn try_from(content: Vec<u8>) -> Result<Self> {
        let checksum = checksum(&content)?;
        let path = PathBuf::from(std::env::var("OUT_DIR").context("missing OUT_DIR")?).join(&checksum);
        write_if_changed(&path, &content)
            .with_context(|| format!("failed to write {}", path.display()))?;
        Ok(Self { checksum })
    }
}

impl quote::ToTokens for Cached {
    fn to_tokens(&self, tokens: &mut proc_macro2::TokenStream) {
        let checksum = &self.checksum;
        tokens.append_all(quote!(::std::concat!(::std::env!("OUT_DIR"), "/", #checksum)));
    }
}

enum IconFormat {
    Raw,
    Image { width: u32, height: u32 },
}

struct CachedIcon {
    cache: Cached,
    format: IconFormat,
    root: proc_macro2::TokenStream,
}

impl CachedIcon {
    fn new(root: &proc_macro2::TokenStream, icon: &Path) -> Result<Self> {
        match icon.extension().and_then(OsStr::to_str) {
            Some("png") => Self::new_png(root, icon),
            Some("ico") => bail!("ico icons are not supported by this tool"),
            Some(other) => bail!(
                "unsupported icon extension `{other}` for {}",
                icon.display()
            ),
            None => bail!("icon {} has no extension", icon.display()),
        }
    }

    fn new_raw(root: &proc_macro2::TokenStream, icon: &Path) -> Result<Self> {
        let buf = fs::read(icon).with_context(|| format!("failed to open icon {}", icon.display()))?;
        Cached::try_from(buf).map(|cache| Self {
            cache,
            root: root.clone(),
            format: IconFormat::Raw,
        })
    }

    fn new_png(root: &proc_macro2::TokenStream, icon: &Path) -> Result<Self> {
        let buf = fs::read(icon).with_context(|| format!("failed to open icon {}", icon.display()))?;
        let decoder = png::Decoder::new(Cursor::new(&buf));
        let mut reader = decoder
            .read_info()
            .unwrap_or_else(|e| panic!("failed to read icon {}: {}", icon.display(), e));

        if reader.output_color_type().0 != png::ColorType::Rgba {
            panic!("icon {} is not RGBA", icon.display());
        }

        let mut rgba = Vec::with_capacity(reader.output_buffer_size());
        while let Ok(Some(row)) = reader.next_row() {
            rgba.extend(row.data());
        }

        Cached::try_from(rgba).map(|cache| Self {
            cache,
            root: root.clone(),
            format: IconFormat::Image {
                width: reader.info().width,
                height: reader.info().height,
            },
        })
    }
}

impl quote::ToTokens for CachedIcon {
    fn to_tokens(&self, tokens: &mut proc_macro2::TokenStream) {
        let root = &self.root;
        let cache = &self.cache;
        let raw = quote!(::std::include_bytes!(#cache));
        tokens.append_all(match self.format {
            IconFormat::Raw => raw,
            IconFormat::Image { width, height } => {
                quote!(#root::image::Image::new(#raw, #width, #height))
            }
        });
    }
}

fn checksum(bytes: &[u8]) -> Result<String> {
    let mut hex = String::with_capacity(64);
    for byte in blake3::hash(bytes).as_bytes() {
        write!(hex, "{byte:02x}")?;
    }
    Ok(hex)
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
    let source_bytes =
        fs::read(path).with_context(|| format!("failed to read {}", path.display()))?;
    let source = String::from_utf8(source_bytes.clone())
        .with_context(|| format!("failed to decode {}", path.display()))?;
    let file =
        syn::parse_file(&source).with_context(|| format!("failed to parse {}", path.display()))?;
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

#[cfg(test)]
mod tests {
    use super::uses_default_config_layout;
    use std::path::Path;

    #[test]
    fn default_config_layout_is_detected_by_filename() {
        assert!(uses_default_config_layout(Path::new(
            "/tmp/app/src-tauri/tauri.conf.json"
        )));
        assert!(!uses_default_config_layout(Path::new(
            "/tmp/app/src-tauri/tauri.macos.conf.json"
        )));
        assert!(!uses_default_config_layout(Path::new(
            "/tmp/app/src-tauri/custom.json"
        )));
    }
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
        bail!(
            "expected tuple with {count} elements, got {}",
            tuple.elems.len()
        );
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
