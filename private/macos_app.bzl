load("//tauri:providers.bzl", "MacosAppBundleInfo", "TauriBundleInfo")

def tauri_macos_app_impl(ctx):
    bundle = ctx.attr.bundle[TauriBundleInfo]
    app_bundle = ctx.actions.declare_directory("%s.app" % ctx.label.name)
    app_manifest = ctx.actions.declare_file("%s_app_manifest.json" % ctx.label.name)

    ctx.actions.run_shell(
        inputs = [bundle.bundle_inputs_dir, bundle.bundle_manifest],
        outputs = [app_bundle, app_manifest],
        command = """
set -eu
mkdir -p "$1"
cp -R "$2"/Contents "$1/Contents"
cp "$3" "$4"
""",
        arguments = [
            app_bundle.path,
            bundle.bundle_inputs_dir.path,
            bundle.bundle_manifest.path,
            app_manifest.path,
        ],
        mnemonic = "TauriAssembleMacosApp",
        progress_message = "Assembling macOS app bundle for %s" % ctx.label.name,
    )

    return [
        DefaultInfo(files = depset([app_bundle, app_manifest])),
        MacosAppBundleInfo(
            app_bundle = app_bundle,
            bundle_id = bundle.bundle_id,
            product_name = bundle.product_name,
            version = bundle.version,
            target_triple = bundle.target_triple,
            info_plist = bundle.info_plist,
            manifest = app_manifest,
        ),
    ]
