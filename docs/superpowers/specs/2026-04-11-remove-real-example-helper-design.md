# Remove Real Example Helper Design

## Goal

Remove `upstream_build.rs` from the real `examples/tauri_with_vite` build path so Bazel becomes the sole generator of the real example’s full Tauri context, while keeping the fixture helper path as the smaller upstream oracle.

## Non-Goals

- Removing the helper path from `test/fixtures/tauri_codegen` in this step
- Replacing every upstream Tauri compile-time crate across the repository
- Changing the public `rules_tauri` API
- Changing the example app’s runtime behavior or user-facing UI

## Recommended Approach

Keep the fixture helper as the upstream oracle, but remove the helper from the real example only.

That means:

1. `examples/tauri_with_vite` no longer has `upstream_build.rs` or `upstream_build_script`.
2. Bazel generates the real example’s full `tauri-build-context.rs` directly.
3. The real example `build.rs` stays as a thin staging layer that copies Bazel-generated artifacts into `OUT_DIR` and emits the expected `cargo:` contract.
4. Upstream parity remains enforced at the app level through the existing parity script and at the seam level through the fixture oracle.

This removes the helper dependency from the realistic example without giving up the narrowest upstream comparison target.

## Architecture

### Real example

The real example becomes fully Bazel-owned at the full-context boundary:

- Bazel generates:
  - embedded-assets Rust
  - full context Rust
  - any required side artifacts currently copied from the helper out-dir
- the real example `build.rs`:
  - copies those Bazel-generated files into `OUT_DIR`
  - emits the same build-script sidecar contract the compiled crate expects
  - falls back to upstream cargo behavior only for plain cargo/parity execution if required

### Fixture

The fixture remains the upstream oracle target:

- `upstream_build.rs` stays
- helper-generated context stays
- focused seam comparisons stay

This preserves a smaller debugging surface while the real example sheds its helper dependency.

## Required Build Graph Changes

In `examples/tauri_with_vite/app/src-tauri/BUILD.bazel`:

- remove `upstream_build.rs` from `cargo_srcs`
- remove `upstream_build_script`
- replace `full_context_rust` inputs so it no longer depends on the helper target
- add or reuse Bazel-generated inputs for any helper out-dir files the real build path still needs
- change `build_script` `data`, `compile_data`, and `build_script_env` so it no longer references helper paths

## Required `build.rs` Changes

`examples/tauri_with_vite/app/src-tauri/build.rs` should:

- stop reading `RULES_TAURI_BAZEL_UPSTREAM_OUT_DIR`
- stop copying helper out-dir files
- instead read only Bazel-generated inputs
- continue emitting the build-script contract the compiled crate expects
- preserve the cargo fallback path used by `compare_tauri_parity.sh`

## Testing

Keep these green:

- `./test/validate_rules_rust_codegen_fixture.sh`
- `./test/compare_context_build_config.sh`
- `./test/compare_acl_resolution.sh`
- `./test/compare_runtime_authority_resolution.sh`
- `./test/compare_full_codegen_context.sh`
- `./test/validate_examples.sh`
- `./test/compare_tauri_parity.sh`

Update the real-example validation guardrail:

- today it compares active build-script sidecars with helper sidecars
- after helper removal, it should compare the real example’s active sidecars against explicit expected outputs or another Bazel-owned oracle for the real example

The fixture remains the seam-level oracle. The real example keeps the full app-level oracle.

## Risks

### Losing hidden helper outputs

The helper currently supplies more than `tauri-build-context.rs`; it also produces out-dir artifacts and build-script sidecar metadata. Removing it from the real example means Bazel must explicitly generate or preserve everything the runtime path still needs.

### Contract regression

The current real-example guardrail is helper-based. Removing the helper means we need a replacement assertion, or the real path will become easier to drift.

### Cargo fallback drift

The real example still needs to cooperate with the upstream cargo parity path. The fallback behavior in `build.rs` must remain compatible with `compare_tauri_parity.sh`.

## Success Criteria

This step is complete when:

- `examples/tauri_with_vite/app/src-tauri/upstream_build.rs` is removed
- `examples/tauri_with_vite/app/src-tauri/BUILD.bazel` no longer defines `upstream_build_script`
- the real example still builds and launches under Bazel
- `./test/compare_tauri_parity.sh` still passes
- the fixture helper path remains intact and green
- the real example still has a direct contract/parity guardrail after helper removal
