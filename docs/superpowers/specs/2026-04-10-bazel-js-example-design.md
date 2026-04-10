# Bazel-Managed JS Example Design

## Goal

Remove host `bun` from the `examples/tauri_with_vite` build path so the example frontend is built by a Bazel-managed JS toolchain instead of a discovered user-installed binary.

## Problem

The current example is only partially Bazel-native on the JS side:

- Bazel orchestrates the frontend build.
- The actual tool execution still shells out through a host `bun` binary.
- The host tool is discovered outside the lockfile-driven build graph.

This means the realistic example is still not fully aligned with Bazel's usual fast/correct model for JavaScript.

## Constraints

- Do not expand `rules_tauri` public scope beyond Tauri release assembly.
- Keep examples using the public interface.
- Preserve the existing realistic example and parity checks.
- Keep dependency source of truth in `package.json` and the checked-in lockfile.
- Avoid reintroducing checked-in build outputs.

## Recommendation

Adopt a Bazel-managed JS toolchain for the example frontend, driven by the app's lockfile, and use pnpm as the example's package-manager source of truth outside the Bazel build.

Concretely:

- Add a Bazel JS ruleset and pinned Node toolchain.
- Ingest `examples/tauri_with_vite/app/package.json` plus `pnpm-lock.yaml` into Bazel.
- Replace the host-`bun` frontend wrapper path with a Bazel target that runs Vite from Bazel-managed dependencies.
- Keep `tauri-cli` usage limited to the parity test oracle.

## Alternatives Considered

### 1. Keep host `bun` but tighten wrappers

This is cheap but still not hermetic. It does not close the actual gap.

### 2. Use a Bazel JS ruleset with lockfile ingestion

This is the recommended path. It matches normal Bazel JS practice: package manager resolves dependencies, Bazel consumes the lockfile and runs builds through a pinned toolchain.

### 3. Vendor JS tool binaries or prebuilt dependency trees

This would be awkward, high-churn, and less representative of a real consumer setup.

## Proposed Architecture

### JS Dependency Model

- `examples/tauri_with_vite/app/package.json` remains the dependency manifest.
- `examples/tauri_with_vite/app/pnpm-lock.yaml` remains the lockfile source of truth.
- Bazel ingests that lockfile into an external repository for the example's JS dependencies.

### JS Toolchain Model

- Bazel provides a pinned Node runtime.
- Vite and its dependencies are executed from Bazel-managed external repositories.
- No host `bun` discovery is used for the normal example build.

### Example Build Graph

The realistic example should become:

1. Bazel JS rules build `//examples/tauri_with_vite/app:dist`
2. `rules_rust` builds `//examples/tauri_with_vite/app/src-tauri:tauri_with_vite_bin`
3. `rules_tauri` assembles `//examples/tauri_with_vite:app_arm64` and `:app_x86_64`

This keeps the separation clean:

- JS rules own frontend build
- `rules_rust` owns Rust/Tauri compilation
- `rules_tauri` owns `.app` assembly

## Expected File Changes

- `MODULE.bazel`
  - add Bazel JS dependency/toolchain setup
  - remove host `bun` extension usage
- `examples/tauri_with_vite/app/BUILD.bazel`
  - replace custom frontend wrapper usage with Bazel JS rule targets
- `examples/tauri_with_vite/example_build.bzl`
  - remove `example_frontend_dist`
  - keep only the cross-platform single-file helper if still needed
- `tools/build_tauri_example_frontend.sh`
  - delete if no longer referenced
- `tools/extensions.bzl`
  - delete if no longer referenced
- docs/tests
  - update wording to say the realistic example frontend is Bazel-managed

## Verification

The change is complete when all of these remain green:

- `./test/validate_examples.sh`
- `./test/validate_rules_rust_codegen_fixture.sh`
- `./test/compare_tauri_parity.sh`

And additionally:

- the normal example build path no longer depends on host `bun`
- the only remaining `tauri-cli` use is in the parity test oracle

## Non-Goals

- Replacing the parity test's upstream `tauri build` oracle
- Replacing the user-facing package manager workflow
- Turning `rules_tauri` into a JS build ruleset
- Broadening public `rules_tauri` API for example-specific JS concerns
