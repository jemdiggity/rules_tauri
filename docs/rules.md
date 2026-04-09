# Rule Reference

## `tauri_bundle_inputs`

Normalizes Tauri-specific packaging inputs into a deterministic staging tree and manifest for one target triple.

### Attrs

- `frontend_dist`
- `main_binary`
- `sidecars`
- `resources`
- `resource_map`
- `resource_trees`
- `icons`
- `tauri_config`
- `capabilities`
- `entitlements`
- `info_plist_fragments`
- `macos_files`
- `bundle_id`
- `product_name`
- `version`
- `version_file`
- `target_triple`
- `frameworks`

### Outputs

- bundle input directory
- bundle manifest
- generated `Info.plist`

## `tauri_macos_app`

Assembles an unsigned macOS `.app` from `TauriBundleInfo`.

### Attrs

- `bundle`

### Outputs

- unsigned `.app`
- app manifest
