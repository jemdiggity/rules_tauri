"""plist generation and merge helpers for rules_tauri internals."""

def default_plist_inputs(bundle_id, product_name, version, main_binary_name):
    return {
        "bundle_id": bundle_id,
        "product_name": product_name,
        "version": version,
        "main_binary_name": main_binary_name,
    }
