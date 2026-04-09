TauriBundleInfo = provider(
    doc = "Normalized Tauri bundle inputs for one target triple.",
    fields = {
        "bundle_inputs_dir": "Directory containing normalized bundle inputs.",
        "bundle_manifest": "Manifest describing staged inputs and destinations.",
        "main_binary": "Main application binary file.",
        "sidecars": "List of staged sidecar files.",
        "bundle_id": "Bundle identifier.",
        "product_name": "Product name.",
        "version": "Application version.",
        "target_triple": "Target triple for this bundle.",
        "info_plist": "Generated Info.plist file.",
        "entitlements": "Optional entitlements file.",
        "main_binary_name": "Basename used for the main app executable.",
    },
)

MacosAppBundleInfo = provider(
    doc = "Unsigned macOS app bundle output.",
    fields = {
        "app_bundle": "Directory representing the unsigned .app bundle.",
        "bundle_id": "Bundle identifier.",
        "product_name": "Product name.",
        "version": "Application version.",
        "target_triple": "Target triple for this app bundle.",
        "info_plist": "Final Info.plist file.",
        "manifest": "Bundle manifest file.",
    },
)
