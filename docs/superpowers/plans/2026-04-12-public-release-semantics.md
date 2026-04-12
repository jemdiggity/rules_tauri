# Public Release Semantics Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract the Vite example's Bazel-native Tauri release glue into additive public APIs and migrate the example to use them.

**Architecture:** Keep compilation downstream, but expose public rules for typed sidecars, release context generation, and release wrapper source generation. Build a thin `tauri_app` macro over the existing bundle rules so normal consumers describe an app rather than raw bundle internals.

**Tech Stack:** Starlark rules/macros, existing Rust codegen tools, Bazel genrules, example validation scripts

---

### Task 1: Update repo contract and public API scaffolding

**Files:**
- Modify: `AGENTS.md`
- Modify: `tauri/defs.bzl`
- Modify: `tauri/providers.bzl`

- [ ] Add the broadened release-semantics scope to `AGENTS.md`.
- [ ] Define new public providers for typed sidecars and release-context outputs in `tauri/providers.bzl`.
- [ ] Export placeholders or final implementations for `tauri_sidecar`, `tauri_release_context`, `tauri_release_rust_library_src`, and `tauri_app` from `tauri/defs.bzl`.

### Task 2: Extract sidecar and release-codegen rules from example glue

**Files:**
- Create: `private/sidecar.bzl`
- Create: `private/release_context.bzl`
- Modify: `private/upstream_context_oracle.bzl`
- Modify: `tauri/defs.bzl`

- [ ] Move sidecar staging/validation logic into a dedicated private rule and expose it publicly.
- [ ] Move release context generation into a dedicated private rule that returns the full-context file and support directory.
- [ ] Move release wrapper source generation out of the example and into a reusable private rule.
- [ ] Reuse existing codegen tools rather than adding new example-specific tooling.

### Task 3: Add high-level app macro and preserve existing low-level rules

**Files:**
- Modify: `tauri/defs.bzl`
- Modify: `private/bundle_inputs.bzl`

- [ ] Add a `tauri_app` macro that materializes `*_bundle_inputs` and `*_app`.
- [ ] Allow `tauri_bundle_inputs` to consume typed sidecar providers without breaking raw-file sidecar support.
- [ ] Keep `tauri_bundle_inputs` and `tauri_macos_app` stable for advanced users.

### Task 4: Migrate the example to public APIs

**Files:**
- Modify: `examples/tauri_with_vite/BUILD.bazel`
- Modify: `examples/tauri_with_vite/app/src-tauri/BUILD.bazel`

- [ ] Replace example-local release wrapper genrule glue with the new public release-source rule.
- [ ] Keep the dev-oriented `build.rs` path for Tauri CLI use.
- [ ] Keep the Bazel release path free of local Cargo build-script wiring.
- [ ] Use the new top-level `tauri_app` macro where it improves the example.

### Task 5: Update validations and verify determinism

**Files:**
- Modify: `test/validate_examples.sh`
- Modify: `test/validate_direct_context_codegen.sh`

- [ ] Update tests to assert the example depends on the new public APIs instead of local glue.
- [ ] Run the example validation and direct context validation.
- [ ] Inspect outputs and keep the change additive and deterministic.
