# More Permissive `frontend_dist` Design

## Goal

Allow `tauri_application()` to accept `frontend_dist` as either:

- a single directory-producing target, or
- a flat set of files

while keeping the public attribute name unchanged and moving frontend normalization plus embedded-assets generation into `rules_tauri`.

## Motivation

The current `tauri_application()` API requires consumers to precompute two distinct frontend-facing inputs:

- `frontend_dist`
- `embedded_assets_rust`

That is too low-level for the intended standard-layout path. It also exposes a footgun: when `frontend_dist` is a file target rather than a directory target, downstream asset generation can preserve the wrong logical root and break runtime lookups such as `index.html`.

The examples currently demonstrate both shapes:

- `examples/tauri_with_vite` uses a directory-shaped frontend target.
- `examples/minimal_macos` needed extra glue to normalize a static `index.html` into a directory artifact.

That normalization burden should live in `rules_tauri`, not in consuming repos.

## Public API Changes

### `tauri_application()`

Keep `frontend_dist` as the public attribute name, but make the accepted input more permissive:

- If the target produces exactly one directory artifact, use it directly.
- Otherwise, treat the target's files as a flat file set and normalize them into a synthetic directory artifact inside `rules_tauri`.

Remove `embedded_assets_rust` from the required public API of `tauri_application()`. The macro should generate it internally from the normalized frontend tree.

### Lower-Level APIs

Keep lower-level APIs additive and conservative:

- `tauri_app()` remains packaging-only and unchanged.
- `tauri_release_context()` and `tauri_rust_app()` should move toward the same internal normalization path so the high-level and lower-level release flows do not diverge.
- If an explicit embedded-assets seam is still needed for escape hatches, keep it private or lower-level rather than in the default high-level path.

## Architecture

Add one private frontend-normalization primitive that accepts a target and emits exactly one directory artifact with stable relative paths.

`tauri_application()` should:

1. normalize `frontend_dist` to a directory artifact
2. generate `embedded_assets_rust` internally from that normalized directory
3. pass the normalized directory into ACL prep, oracle/context generation, and any other frontend-path-sensitive release logic

This keeps one canonical frontend shape inside `rules_tauri` even if the user input shape varies.

## Path Semantics

For directory-producing targets:

- preserve the existing tree as-is

For file-set targets:

- preserve file basenames and relative paths using a caller-independent deterministic strategy
- require a stable common root inference or explicit rule-side preservation strategy
- ensure a single `index.html` file results in the logical asset path `/index.html`

The normalized output must be deterministic:

- stable sort order
- stable destination paths
- no ambient filesystem dependence

## Implementation Boundaries

### Files Likely To Change

- `tauri/defs.bzl`
- `private/release_context.bzl`
- `private/upstream_context_oracle.bzl`
- new private frontend normalization helper, likely under `private/`
- possibly `private/bundle_inputs.bzl` if any assumptions about `frontend_dist` shape are still present
- examples:
  - `examples/minimal_macos/BUILD.bazel`
  - `examples/minimal_macos/src-tauri/BUILD.bazel`
  - `examples/tauri_with_vite/app/src-tauri/BUILD.bazel`
- docs:
  - `README.md`
  - example READMEs
- tests:
  - `test/validate_examples.sh`

### Files That Should Go Away Or Simplify

- `examples/minimal_macos/example_build.bzl` should become unnecessary once `rules_tauri` owns frontend normalization.

## Testing Strategy

Keep example coverage and add focused regression coverage.

### Required Checks

- `minimal_macos` still builds and runs through `tauri_application()`
- `tauri_with_vite` still builds and runs through `tauri_application()`
- generated embedded assets for the static example include `/index.html`
- directory-producing frontend targets still behave identically
- output remains deterministic for both frontend input shapes

### Regression Focus

The runtime error `asset not found: index.html` must be prevented by a direct regression check in the generated embedded-assets output, not only by manual app launch.

## Compatibility

This is intended to be additive for consumers of `tauri_application()`:

- existing directory-shaped `frontend_dist` users should continue to work
- users with plain file targets should start working without extra helper rules

This should reduce consumer BUILD boilerplate without broadening scope beyond release semantics.

## Non-Goals

- taking ownership of frontend compilation
- changing `tauri_app()` into a compile rule
- adding dev-workflow support
- expanding scope beyond unsigned macOS `.app` release assembly plus current Bazel-owned release semantics
