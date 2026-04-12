# rules_tauri

Release-focused Bazel rules for Tauri applications.

`rules_tauri` owns Tauri release semantics short of compilation. It now provides both:

- packaging rules for users who already have a release binary
- Bazel-native release helpers for standard-layout Tauri Rust apps

Its scope is:

- accept already-built frontend assets, Rust binaries, sidecars, and Tauri metadata,
- optionally generate Bazel-owned Tauri release context and release crate roots for standard `src-tauri` apps,
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
load("@rules_tauri//tauri:defs.bzl", "tauri_application")
```

Preferred entrypoints:

- `tauri_application`
  - standard-layout Tauri Rust app
  - Bazel owns release context/codegen and app bundle assembly
- `tauri_app`
  - you already have a release binary and want app bundle assembly only

Lower-level escape hatches:

- `tauri_rust_app`
- `tauri_release_context`
- `tauri_release_rust_library_src`
- `tauri_sidecar`
- `tauri_bundle_inputs`
- `tauri_macos_app`

## Typical Usage

For a normal Tauri app with a standard `src-tauri` layout, use `tauri_application(...)`.
The consuming repo still owns:

- frontend build
- Rust dependency declarations
- optional Cargo/Tauri CLI dev workflow

`rules_tauri` then owns the Bazel-native release context generation, release source rewriting, release binary wiring, and unsigned `.app` assembly.

For a repo that already has a suitable release binary, use `tauri_app(...)` directly instead.

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
- [`examples/tauri_with_vite`](examples/tauri_with_vite) vendors a real `create tauri-app` Vue/Vite project and uses the high-level `tauri_application` macro for its release path
- [`test/fixtures/tauri_codegen`](test/fixtures/tauri_codegen) isolates Tauri codegen and embedded-asset behavior under `rules_rust`
