mod build_contract;

use std::fs;
use std::path::{Path, PathBuf};

fn copy_tree(source: &Path, destination: &Path) {
    if source.is_dir() {
        fs::create_dir_all(destination).unwrap_or_else(|error| {
            panic!(
                "failed to create destination directory {}: {error}",
                destination.display()
            )
        });
        for entry in fs::read_dir(source).unwrap_or_else(|error| {
            panic!("failed to read source directory {}: {error}", source.display())
        }) {
            let entry = entry.unwrap_or_else(|error| {
                panic!("failed to read entry from {}: {error}", source.display())
            });
            copy_tree(&entry.path(), &destination.join(entry.file_name()));
        }
        return;
    }

    let parent = destination.parent().expect("destination must have a parent");
    fs::create_dir_all(parent).unwrap_or_else(|error| {
        panic!(
            "failed to create destination parent {}: {error}",
            parent.display()
        )
    });
    fs::copy(source, destination).unwrap_or_else(|error| {
        panic!(
            "failed to copy {} to {}: {error}",
            source.display(),
            destination.display()
        )
    });
}

fn copy_bazel_out_dir(bazel_out_dir: &Path, out_dir: &Path) {
    for entry in fs::read_dir(bazel_out_dir).unwrap_or_else(|error| {
        panic!(
            "failed to read Bazel out dir {}: {error}",
            bazel_out_dir.display()
        )
    }) {
        let entry = entry.unwrap_or_else(|error| {
            panic!(
                "failed to read entry from Bazel out dir {}: {error}",
                bazel_out_dir.display()
            )
        });
        let path = entry.path();
        if path.file_name().and_then(|name| name.to_str()) == Some("tauri-build-context.rs") {
            continue;
        }

        let destination = out_dir.join(entry.file_name());
        copy_tree(&path, &destination);
    }
}

fn emit_upstream_contract(out_dir: &Path) {
    let config: serde_json::Value =
        serde_json::from_str(&fs::read_to_string("tauri.conf.json").expect("failed to read tauri.conf.json"))
            .expect("failed to parse tauri.conf.json");
    let identifier = config["identifier"]
        .as_str()
        .expect("tauri.conf.json must contain identifier");
    let (android_package_name_app_name, android_package_name_prefix) =
        build_contract::android_package_names(identifier);
    let target_os = std::env::var("CARGO_CFG_TARGET_OS").expect("missing CARGO_CFG_TARGET_OS");
    let mobile = target_os == "ios" || target_os == "android";

    println!("cargo:rustc-check-cfg=cfg(desktop)");
    println!("cargo:rustc-check-cfg=cfg(mobile)");
    if mobile {
        println!("cargo:rustc-cfg=mobile");
    } else {
        println!("cargo:rustc-cfg=desktop");
    }
    println!("cargo:rustc-check-cfg=cfg(dev)");
    if build_contract::is_dev_enabled(std::env::var("DEP_TAURI_DEV").ok().as_deref()) {
        println!("cargo:rustc-cfg=dev");
    }
    println!(
        "cargo:rustc-env=TAURI_ANDROID_PACKAGE_NAME_APP_NAME={}",
        android_package_name_app_name
    );
    println!(
        "cargo:rustc-env=TAURI_ANDROID_PACKAGE_NAME_PREFIX={}",
        android_package_name_prefix
    );
    if let Ok(target) = std::env::var("TARGET") {
        println!("cargo:rustc-env=TAURI_ENV_TARGET_TRIPLE={target}");
    }
    println!(
        "cargo:PERMISSION_FILES_PATH={}",
        out_dir
            .join("app-manifest")
            .join("__app__-permission-files")
            .display()
    );
}

fn extract_quoted_name_after(text: &str, marker: &str) -> Option<String> {
    let start = text.find(marker)? + marker.len();
    let end = text[start..].find('"')?;
    Some(text[start..start + end].to_string())
}

fn first_icon_path<F>(predicate: F) -> PathBuf
where
    F: Fn(&str) -> bool,
{
    let config: serde_json::Value =
        serde_json::from_str(&fs::read_to_string("tauri.conf.json").expect("failed to read tauri.conf.json"))
            .expect("failed to parse tauri.conf.json");
    let icons = config["bundle"]["icon"]
        .as_array()
        .expect("tauri.conf.json must contain bundle.icon");
    let icon = icons
        .iter()
        .filter_map(|value| value.as_str())
        .find(|path| predicate(path))
        .expect("failed to locate matching icon in tauri.conf.json");
    PathBuf::from(icon)
}

fn decode_png_to_rgba(path: &Path) -> Vec<u8> {
    let data = fs::read(path)
        .unwrap_or_else(|error| panic!("failed to read {}: {error}", path.display()));
    let decoder = png::Decoder::new(std::io::Cursor::new(data));
    let mut reader = decoder
        .read_info()
        .unwrap_or_else(|error| panic!("failed to decode {}: {error}", path.display()));
    let mut rgba = Vec::with_capacity(reader.output_buffer_size());
    while let Ok(Some(row)) = reader.next_row() {
        rgba.extend_from_slice(row.data());
    }
    rgba
}

fn ensure_generated_support_files(out_dir: &Path, context_path: &Path) {
    let context = fs::read_to_string(context_path).unwrap_or_else(|error| {
        panic!(
            "failed to read generated context {}: {error}",
            context_path.display()
        )
    });

    let plist_marker =
        "embed_info_plist ! (:: std :: concat ! (:: std :: env ! (\"OUT_DIR\") , \"/\" , \"";
    if let Some(file_name) = extract_quoted_name_after(&context, plist_marker) {
        let path = out_dir.join(file_name);
        if !path.exists() {
            let package_name = std::env::var("CARGO_PKG_NAME").expect("missing CARGO_PKG_NAME");
            let package_version =
                std::env::var("CARGO_PKG_VERSION").expect("missing CARGO_PKG_VERSION");
            let plist = format!(
                concat!(
                    "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n",
                    "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" ",
                    "\"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n",
                    "<plist version=\"1.0\">\n",
                    "<dict>\n",
                    "\t<key>CFBundleName</key>\n",
                    "\t<string>{}</string>\n",
                    "\t<key>CFBundleShortVersionString</key>\n",
                    "\t<string>{}</string>\n",
                    "\t<key>CFBundleVersion</key>\n",
                    "\t<string>{}</string>\n",
                    "</dict>\n",
                    "</plist>\n"
                ),
                package_name,
                package_version,
                package_version,
            );
            fs::write(&path, plist)
                .unwrap_or_else(|error| panic!("failed to write {}: {error}", path.display()));
        }
    }

    let include_bytes_marker =
        "include_bytes ! (:: std :: concat ! (:: std :: env ! (\"OUT_DIR\") , \"/\" , \"";
    let mut search = context.as_str();
    let mut missing_raw_targets = Vec::new();
    let mut missing_rgba_targets = Vec::new();
    while let Some(offset) = search.find(include_bytes_marker) {
        let remainder = &search[offset + include_bytes_marker.len()..];
        let Some(end) = remainder.find('"') else {
            break;
        };
        let candidate = &remainder[..end];
        if !out_dir.join(candidate).exists() {
            if remainder[end..].contains(". to_vec ())") {
                missing_raw_targets.push(candidate.to_string());
            } else {
                missing_rgba_targets.push(candidate.to_string());
            }
        }
        search = &remainder[end..];
    }

    let raw_icon_path = first_icon_path(|path| path.ends_with(".icns"));
    for file_name in missing_raw_targets {
        let destination = out_dir.join(file_name);
        fs::copy(&raw_icon_path, &destination).unwrap_or_else(|error| {
            panic!(
                "failed to copy {} to {}: {error}",
                raw_icon_path.display(),
                destination.display()
            )
        });
    }

    let rgba_icon = decode_png_to_rgba(&first_icon_path(|path| path.ends_with(".png")));
    for file_name in missing_rgba_targets {
        let destination = out_dir.join(file_name);
        fs::write(&destination, &rgba_icon).unwrap_or_else(|error| {
            panic!("failed to write {}: {error}", destination.display())
        });
    }
}

fn main() {
    if let Ok(manifest_dir) = std::env::var("CARGO_MANIFEST_DIR") {
        std::env::set_current_dir(&manifest_dir)
            .unwrap_or_else(|error| panic!("failed to chdir to {manifest_dir}: {error}"));
    }

    if std::env::var_os("RULES_TAURI_BAZEL_FULL_CONTEXT").is_none() {
        let attributes = tauri_build::Attributes::new().codegen(tauri_build::CodegenContext::new());
        tauri_build::try_build(attributes).expect("failed to generate Tauri build context");
        return;
    }

    println!("cargo:rerun-if-env-changed=TAURI_CONFIG");
    println!("cargo:rerun-if-env-changed=REMOVE_UNUSED_COMMANDS");
    println!("cargo:rerun-if-changed=tauri.conf.json");
    println!("cargo:rerun-if-changed=capabilities");
    println!("cargo:rerun-if-changed=../dist");

    let full_context_path =
        std::env::var("RULES_TAURI_BAZEL_FULL_CONTEXT").expect("missing RULES_TAURI_BAZEL_FULL_CONTEXT");
    println!("cargo:rerun-if-env-changed=RULES_TAURI_BAZEL_FULL_CONTEXT");
    println!("cargo:rerun-if-changed={full_context_path}");
    let acl_out_dir = PathBuf::from(
        std::env::var("RULES_TAURI_BAZEL_ACL_OUT_DIR")
            .expect("missing RULES_TAURI_BAZEL_ACL_OUT_DIR"),
    );
    println!("cargo:rerun-if-env-changed=RULES_TAURI_BAZEL_ACL_OUT_DIR");
    println!("cargo:rerun-if-changed={}", acl_out_dir.display());

    let out_dir = PathBuf::from(std::env::var("OUT_DIR").expect("missing OUT_DIR"));
    let out_path = out_dir.join("tauri-build-context.rs");
    fs::copy(&full_context_path, &out_path).unwrap_or_else(|error| {
        panic!(
            "failed to copy {} to {}: {error}",
            full_context_path,
            out_path.display()
        )
    });

    copy_bazel_out_dir(&acl_out_dir, &out_dir);
    ensure_generated_support_files(&out_dir, &out_path);
    emit_upstream_contract(&out_dir);
}
