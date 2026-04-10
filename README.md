# rules_tauri

Release-focused Bazel rules for Tauri applications.

`rules_tauri` is intentionally narrow. Its v1 scope is:

- accept already-built frontend assets, Rust binaries, sidecars, and Tauri metadata,
- assemble a deterministic unsigned macOS `.app` bundle for one target triple,
- stop at the `.app` boundary.

For normal release apps, `frontend_dist` is treated as an input to upstream-style Tauri asset embedding, not as loose frontend files to copy into the final app bundle.

Everything after `.app` creation, including code signing, DMG creation, notarization, stapling, and release upload, is out of scope.

## Status

The repository now includes a working implementation pass:

- `tauri_bundle_inputs` stages inputs into a deterministic `Contents/...` tree and emits a manifest
- `tauri_macos_app` wraps that staged tree into an unsigned `.app`
- `examples/tauri_with_vite` builds a real Vue/Vite + Tauri app with Bazel-managed frontend and Rust build steps
- the active Bazel example build path no longer depends on `tauri_build::try_build(...)` in its real `build.rs`
- focused oracle tests compare Bazel-owned compile-time seams against upstream Tauri outputs

The implementation currently focuses on:

- resource path normalization
- sidecar staging
- plist generation and merge order
- version sourcing from either an explicit string or a source-of-truth version file
- macOS custom file injection
- framework staging
- Bazel-owned embedded asset generation and context patching under `rules_rust`

It still does not aim for complete upstream Tauri feature parity or full replacement of every upstream compile-time crate.

## Design

See:

- [`docs/design.md`](docs/design.md)
- [`docs/rules.md`](docs/rules.md)
- [`docs/testing.md`](docs/testing.md)

## Public API

```starlark
load("@rules_tauri//tauri:defs.bzl", "tauri_bundle_inputs", "tauri_macos_app")
```

## Current Scope

- macOS release assembly only
- separate `arm64` and `x86_64` outputs
- no universal app support
- no dev workflow support
- no signing, DMG, or notarization logic

## Repository Layout

```text
tauri/
  defs.bzl
  providers.bzl
private/
  bundle_inputs.bzl
  macos_app.bzl
docs/
examples/
test/
tools/
```

## Examples

- [`examples/minimal_macos`](examples/minimal_macos) exercises bundle layout mechanics with simple fixture inputs
- [`examples/tauri_with_vite`](examples/tauri_with_vite) vendors a real `create tauri-app` Vue/Vite project and builds its frontend and Tauri binary from source during Bazel execution
- [`test/fixtures/tauri_codegen`](test/fixtures/tauri_codegen) isolates Tauri codegen and embedded-asset behavior under `rules_rust`
