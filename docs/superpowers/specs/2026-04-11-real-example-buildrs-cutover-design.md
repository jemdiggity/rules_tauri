# Real Example `build.rs` Cutover Design

## Goal

Remove `tauri_build::try_build(...)` from the real `examples/tauri_with_vite` build path while preserving:

- a runnable example app
- Bazel-owned embedded-assets behavior
- parity oracles against upstream Tauri
- the existing repo contract that `rules_tauri` assembles the unsigned `.app` and does not own general dev workflow support

This step applies the same pattern already proven in `test/fixtures/tauri_codegen` to the real example.

## Non-Goals

- Removing all upstream Tauri compile-time code from the repository in this step
- Removing the helper upstream build-script oracle in this step
- Broadening `rules_tauri` public API
- Changing the example app’s user-facing functionality

## Recommended Approach

Keep an example-local upstream helper build script, but remove `tauri_build::try_build(...)` from the real example’s actual `build.rs`.

The real example will follow the fixture pattern:

1. `upstream_build.rs` runs upstream Tauri codegen and emits the helper out-dir contents.
2. A Bazel genrule patches the helper-generated `tauri-build-context.rs`, replacing only the embedded-assets seam.
3. The real example `build.rs` copies the Bazel-generated context and helper out-dir contents into its own `OUT_DIR`.
4. The real example `build.rs` emits the same build-script contract as the helper target.

This preserves an authoritative upstream oracle while making the real example’s active build path Bazel-owned at the full-context boundary.

## Build Graph Changes

In `examples/tauri_with_vite/app/src-tauri/BUILD.bazel`:

- Add `upstream_build.rs` to the source set.
- Add `build_contract.rs` if shared build-script contract logic is needed.
- Add a separate `cargo_build_script(name = "upstream_build_script", ...)`.
- Add a Bazel-generated `full_context_rust` target that consumes:
  - the helper-generated `tauri-build-context.rs`
  - the existing Bazel-owned embedded-assets Rust
- Change the real `build_script` target so it consumes:
  - `:full_context_rust`
  - `:upstream_build_script`
  - existing example inputs

The example binary and bundle targets remain unchanged from the user’s perspective.

## Real `build.rs` Behavior

The real example `build.rs` will stop calling `tauri_build::try_build(...)`.

Instead it will:

- change into `CARGO_MANIFEST_DIR`
- emit the expected `cargo:rerun-if-*` lines
- copy the Bazel-generated `tauri-build-context.rs` into its own `OUT_DIR`
- copy helper-generated side outputs into its own `OUT_DIR`
- emit the same effective build-script metadata contract as the helper:
  - `rustc-cfg`
  - `rustc-check-cfg`
  - `rustc-env`
  - `PERMISSION_FILES_PATH`

As with the fixture, the goal is not merely “compiles”, but “matches the helper target’s build-script sidecar outputs.”

## Upstream Helper Behavior

The example-local `upstream_build.rs` will remain the place that calls upstream Tauri compile-time generation.

It will:

- apply the current Bazel `frontendDist` override
- call `tauri_build::try_build(...)`
- normalize generated `BuildConfig.frontend_dist` back to `../dist`

The helper remains the oracle for:

- context shape before Bazel seam replacement
- build-script side outputs
- emitted metadata contract

## Embedded Assets Seam

Keep the existing Bazel-owned embedded-assets replacement exactly as-is in scope:

- asset ordering
- compression
- CSP/hash transforms
- embedded-assets Rust generation

The difference is only where it plugs in:

- today: patch the real build-script output in place
- after cutover: patch the helper-generated context, then hand that result to the real build script

No new embedded-assets semantics are introduced in this step.

## Testing

Keep all existing tests green and add one real-example-specific contract check.

Required green tests:

- `test/validate_examples.sh`
- `test/compare_tauri_parity.sh`
- `test/validate_rules_rust_codegen_fixture.sh`
- fixture oracles already in repo

New test:

- a real-example build-script contract check that compares:
  - `build_script.flags`
  - `build_script.env`
  - normalized `build_script.depenv`
  against the helper target’s corresponding outputs

This mirrors the fixture guardrail and prevents silent drift in the real example cutover.

## Risks

### Contract drift

The real build-script metadata contract can diverge from the helper target even if the app still compiles. This is why the sidecar comparison test is mandatory.

### Context-path drift

The helper-generated context still needs cargo-like normalized paths such as `../dist`. The example helper must preserve the earlier normalization behavior or existing context-oracle/parity checks will regress.

### Runtime regression

The real example must remain launchable. Even if the oracle tests pass, the app must still render correctly after the cutover.

## Success Criteria

This step is complete when:

- the real `examples/tauri_with_vite` `build.rs` no longer calls `tauri_build::try_build(...)`
- the example still builds and runs
- the example still passes parity tests
- a real-example build-script contract test proves the active build-script sidecars match the upstream helper target
- no public `rules_tauri` API changes are required
