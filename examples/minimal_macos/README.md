# minimal_macos

This example demonstrates the default `rules_tauri` consumer path: a standard
`src-tauri` application built with `tauri_application()`, backed by a static
hello-world `index.html`.

It still exercises a small but non-trivial release graph:

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
