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

fn copy_upstream_out_dir(upstream_out_dir: &Path, out_dir: &Path) {
    for entry in fs::read_dir(upstream_out_dir).unwrap_or_else(|error| {
        panic!(
            "failed to read upstream out dir {}: {error}",
            upstream_out_dir.display()
        )
    }) {
        let entry = entry.unwrap_or_else(|error| {
            panic!(
                "failed to read entry from upstream out dir {}: {error}",
                upstream_out_dir.display()
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
    let upstream_out_dir = PathBuf::from(
        std::env::var("RULES_TAURI_BAZEL_UPSTREAM_OUT_DIR")
            .expect("missing RULES_TAURI_BAZEL_UPSTREAM_OUT_DIR"),
    );
    println!("cargo:rerun-if-env-changed=RULES_TAURI_BAZEL_UPSTREAM_OUT_DIR");
    println!("cargo:rerun-if-changed={}", upstream_out_dir.display());

    let out_dir = PathBuf::from(std::env::var("OUT_DIR").expect("missing OUT_DIR"));
    let out_path = out_dir.join("tauri-build-context.rs");
    fs::copy(&full_context_path, &out_path).unwrap_or_else(|error| {
        panic!(
            "failed to copy {} to {}: {error}",
            full_context_path,
            out_path.display()
        )
    });

    copy_upstream_out_dir(&upstream_out_dir, &out_dir);
    emit_upstream_contract(&out_dir);
}
