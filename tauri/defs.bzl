load("//private:bundle_inputs.bzl", "tauri_bundle_inputs_impl")
load("//private:macos_app.bzl", "tauri_macos_app_impl")

tauri_bundle_inputs = rule(
    implementation = tauri_bundle_inputs_impl,
    attrs = {
        "frontend_dist": attr.label(allow_files = True),
        "main_binary": attr.label(allow_single_file = True, mandatory = True),
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
