# Public Release Semantics Design

## Goal

Broaden `rules_tauri` from macOS bundle assembly only to a public API for Tauri release semantics short of compilation. The consuming repo still owns Rust/frontend compilation, but `rules_tauri` owns Bazel-native Tauri release codegen and typed packaging helpers.

## Scope

Additive public API in `//tauri:defs.bzl` and `//tauri:providers.bzl` should cover:

- typed sidecar inputs derived from already-built executables
- Bazel-native Tauri ACL preparation
- Bazel-native Tauri full-context generation
- Bazel-native release wrapper source generation for Rust consumers
- a simpler top-level app macro that produces the final unsigned macOS `.app`

Compilation remains downstream. New APIs should consume files and targets produced by `rules_rust` or any other build rules without depending on compiler-specific internals.

## API Shape

The public surface should keep the existing low-level rules and add:

- `tauri_sidecar`
  - input: executable-producing target plus target triple
  - output: typed provider carrying the staged sidecar file
- `tauri_release_context`
  - input: config, capabilities/icons/config-adjacent cargo sources, frontend dist, embedded assets Rust, ACL dependency env targets
  - output: full-context Rust file and support directory
- `tauri_release_rust_library_src`
  - input: generated full-context support directory and a small wrapper template source
  - output: generated crate-root Rust source for release builds
- `tauri_app`
  - macro over `tauri_bundle_inputs` + `tauri_macos_app`
  - default user-facing entrypoint for packaging

`tauri_bundle_inputs` should accept typed sidecar providers in addition to raw files so existing consumers are not broken.

## Design Notes

- Keep the public contract additive.
- Keep the final `.app` as the main user-facing output.
- Preserve deterministic outputs by continuing to stage all generated support payloads in declared Bazel outputs.
- Do not make `rules_tauri` responsible for local crate `build.rs` execution.
- Do not expose example-specific naming such as `lib_bazel.rs`; expose reusable release-source generation semantics instead.

## Testing

- Keep `examples/` green.
- Add or update tests covering typed sidecars and the extracted release codegen path.
- Preserve direct oracle validation for ACL/context generation.
