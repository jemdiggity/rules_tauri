load("//private:bundle_inputs.bzl", "tauri_bundle_inputs_impl")
load("//private:macos_app.bzl", "tauri_macos_app_impl")
load("//private:release_context.bzl", _tauri_release_context = "tauri_release_context", _tauri_release_rust_library_src = "tauri_release_rust_library_src")
load("//private:sidecar.bzl", "tauri_sidecar_impl")
load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library")

tauri_bundle_inputs = rule(
    implementation = tauri_bundle_inputs_impl,
    attrs = {
        "frontend_dist": attr.label(allow_files = True),
        "main_binary": attr.label(allow_single_file = True, mandatory = True),
        "main_binary_name": attr.string(),
        "sidecars": attr.label_list(allow_files = True),
        "resources": attr.label_list(allow_files = True),
        "resource_map": attr.label_keyed_string_dict(allow_files = True),
        "resource_trees": attr.label_keyed_string_dict(allow_files = True),
        "icons": attr.label_list(allow_files = True),
        "tauri_config": attr.label(allow_single_file = True),
        "capabilities": attr.label_list(allow_files = True),
        "entitlements": attr.label(allow_single_file = True),
        "info_plist_fragments": attr.label_list(allow_files = True),
        "macos_files": attr.label_keyed_string_dict(allow_files = True),
        "bundle_id": attr.string(mandatory = True),
        "product_name": attr.string(mandatory = True),
        "version": attr.string(),
        "version_file": attr.label(allow_single_file = True),
        "target_triple": attr.string(mandatory = True),
        "frameworks": attr.label_list(allow_files = True),
        "_make_manifest_tool": attr.label(
            default = "//tools:make_manifest.py",
            executable = True,
            allow_single_file = True,
            cfg = "exec",
        ),
        "_make_plist_tool": attr.label(
            default = "//tools:make_plist.py",
            executable = True,
            allow_single_file = True,
            cfg = "exec",
        ),
    },
    doc = "Normalizes Tauri packaging inputs into a deterministic staging tree.",
)

tauri_macos_app = rule(
    implementation = tauri_macos_app_impl,
    attrs = {
        "bundle": attr.label(mandatory = True),
    },
    doc = "Assembles an unsigned macOS .app from TauriBundleInfo.",
)

tauri_sidecar = rule(
    implementation = tauri_sidecar_impl,
    attrs = {
        "binary": attr.label(mandatory = True, allow_single_file = True),
        "sidecar_name": attr.string(),
        "target_triple": attr.string(mandatory = True),
    },
    doc = "Stages a built executable as a typed Tauri sidecar input.",
)

def tauri_app(
        *,
        name,
        bundle_inputs_name = None,
        **kwargs):
    bundle_inputs_name = bundle_inputs_name if bundle_inputs_name else name + "_bundle_inputs"
    tauri_bundle_inputs(
        name = bundle_inputs_name,
        **kwargs
    )
    tauri_macos_app(
        name = name,
        bundle = ":" + bundle_inputs_name,
    )

def tauri_rust_app(
        *,
        name,
        cargo_srcs,
        tauri_build_data,
        frontend_dist,
        embedded_assets_rust,
        aliases,
        deps,
        proc_macro_deps,
        binary_name = None,
        context_cargo_srcs = None,
        lib_src = "src/lib.rs",
        main_src = "src/main.rs",
        crate_features = [],
        acl_dep_env_targets = []):
    context_cargo_srcs = context_cargo_srcs if context_cargo_srcs else cargo_srcs
    release_context_name = name + "_release_context"
    release_lib_name = name + "_release_lib"
    binary_name = binary_name if binary_name else name + "_bin"

    tauri_release_context(
        name = release_context_name,
        cargo_srcs = context_cargo_srcs,
        tauri_build_data = tauri_build_data,
        frontend_dist = frontend_dist,
        embedded_assets_rust = embedded_assets_rust,
        acl_dep_env_targets = acl_dep_env_targets,
    )

    tauri_release_rust_library_src(
        name = release_lib_name,
        src = lib_src,
        release_context_support = ":" + release_context_name + "_support",
    )

    rust_library(
        name = name,
        srcs = [":" + release_lib_name],
        crate_root = release_lib_name + ".rs",
        crate_name = name,
        edition = "2021",
        aliases = aliases,
        crate_features = crate_features,
        compile_data = [
            ":" + release_context_name + "_support",
        ],
        deps = deps,
        proc_macro_deps = proc_macro_deps,
    )

    rust_binary(
        name = binary_name,
        srcs = [main_src],
        crate_name = binary_name,
        edition = "2021",
        crate_features = crate_features,
        deps = [":" + name],
    )

tauri_release_context = _tauri_release_context
tauri_release_rust_library_src = _tauri_release_rust_library_src
