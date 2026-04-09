# minimal_macos

This example exercises a small but non-trivial `rules_tauri` graph:

- frontend assets
- main binary
- sidecar
- resources and mapped resources
- icon
- Tauri config
- plist fragment
- macOS custom files
- framework staging

Build with:

```sh
bazel build //examples/minimal_macos:app_arm64 //examples/minimal_macos:app_x86_64
```
