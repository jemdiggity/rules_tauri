# Bazel-Native Tauri Parity Design

## Goal

Make `rules_tauri` match the behavior of `cargo tauri build` for a normal macOS release app, using a Bazel-native implementation rather than shelling out to Tauri's CLI or bundler for the final result.

## Why The Current Design Is Wrong

Today `rules_tauri` treats `frontend_dist` as loose bundle resources under `Contents/Resources/frontend/...`.

That is not how upstream Tauri release builds normally work. In the current upstream Tauri source:

- `tauri-codegen` embeds `frontendDist` into the app context when `devUrl` is absent
- `tauri-build` wires that embedding behavior into build-time code generation
- `tauri-bundler` then assembles the macOS `.app`

For a normal release app, frontend assets are part of the application binary's compiled context, not staged as loose files for runtime lookup.

## Source Of Truth

This design treats the local Tauri checkout at `/Users/jeremyhale/.kanna/repos/tauri` as the primary behavioral reference.

Key upstream files:

- `crates/tauri-codegen/src/context.rs`
- `crates/tauri-codegen/src/embedded_assets.rs`
- `crates/tauri-build/src/codegen/context.rs`
- `crates/tauri-utils/src/resources.rs`
- `crates/tauri-bundler/src/bundle/settings.rs`
- `crates/tauri-bundler/src/bundle/macos/app.rs`

## Target Behavior

For macOS release builds, `rules_tauri` should match upstream in these areas:

1. `frontend_dist` handling
   - release builds embed assets into the generated Tauri context
   - loose frontend files are not copied into `Contents/Resources/frontend/...` for normal release apps

2. Resource handling
   - resources and mapped resources follow upstream normalization semantics from `tauri-utils`

3. Sidecar handling
   - sidecars/external binaries are copied into `Contents/MacOS`
   - target triple suffixes are stripped from bundled sidecar filenames

4. Main binary handling
   - the bundled executable name matches the app's binary naming contract
   - `CFBundleExecutable` matches the actual bundled executable

5. macOS bundle layout
   - `Info.plist` generation and merge order matches upstream bundler behavior
   - frameworks go under `Contents/Frameworks`
   - custom macOS files go under `Contents/...`
   - icons and bundle metadata match upstream conventions closely enough for parity

## Public API Direction

The public API can remain narrow, but its semantics need to shift.

`frontend_dist` should no longer mean "copy these files into the app bundle for release." It should mean "use these files as release asset inputs for Tauri-compatible embedding."

This is a behavior change, but it is justified because the current behavior is not actually compatible with normal Tauri release apps.

## Proposed Architecture

### 1. Add A Tauri Context Generation Step

Introduce a Bazel-managed generation step that mirrors the release path of upstream `tauri-build` and `tauri-codegen`:

- read Tauri config
- resolve `frontend_dist`
- apply upstream-style embedded asset processing
- generate deterministic output files that Rust compilation can consume

The implementation may either:

- invoke a repo-local helper tool that mirrors the relevant upstream logic, or
- directly port the specific upstream logic into tools under `//tools`

The important constraint is that Bazel owns the build graph and declared inputs/outputs.

### 2. Separate Binary Preparation From Bundle Assembly

The current `tauri_bundle_inputs` rule is doing too much conceptually. The design should split:

- binary preparation / release asset embedding
- bundle assembly

That makes the boundary clearer:

- one phase produces a Tauri-compatible release executable
- one phase assembles the macOS `.app` around that executable and companion files

### 3. Align Bundle Assembly With `tauri-bundler`

The macOS assembly logic should match upstream bundler behavior for:

- main binary placement
- external binary placement and renaming
- resources
- frameworks
- custom `macOS.files`
- `Info.plist` defaults and merge order

Signing, notarization, and DMG generation remain out of scope.

## Testing Strategy

The implementation must be driven by parity tests against real upstream output.

For the same sample application:

- build once with `cargo tauri build`
- build once with Bazel
- compare the resulting app bundles on the dimensions that matter

Initial parity checks:

- no loose frontend tree for normal release builds
- same executable filename
- same presence and placement of sidecars/resources/frameworks/custom files
- same key `Info.plist` fields:
  - `CFBundleExecutable`
  - `CFBundleIdentifier`
  - `CFBundleShortVersionString`
  - `CFBundleVersion`
  - `CFBundleIconFile`
  - `LSMinimumSystemVersion` when configured

The tests do not need byte-for-byte bundle identity at first, but they do need strong semantic parity.

## Example Direction

`examples/tauri_with_vite` should evolve from "real fixture inputs" into "real parity example."

That example should be used for:

- upstream `cargo tauri build` reference output
- Bazel parity output
- automated comparison in repository tests

## Risks

- Reimplementing compile-time asset embedding is the highest-risk portion.
- Upstream Tauri behavior will evolve, so parity tests must stay in the repo permanently.
- This is a larger change than the current public API implies, but the current behavior is not actually correct for normal Tauri release apps.
