# Bazel-Native Tauri Parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rework `rules_tauri` so Bazel-native macOS release builds match `cargo tauri build` semantics for a normal Tauri app, including compile-time frontend asset embedding behavior.

**Architecture:** Add a Bazel-managed Tauri-compatible release preparation step for embedded assets, align macOS assembly with upstream `tauri-bundler`, and drive the rewrite with parity tests that compare Bazel output against an upstream-built sample app.

**Tech Stack:** Bazel, Starlark, Python helper tools, Rust/Tauri reference behavior, shell validation

---

### Task 1: Establish A Parity Oracle

**Files:**
- Create: `test/compare_tauri_parity.sh`
- Modify: `examples/tauri_with_vite/README.md`

- [ ] **Step 1: Write a parity script that builds the sample app with upstream Tauri**

Run shape:

```sh
cd examples/tauri_with_vite/app
bun install
bun run build
cd src-tauri
cargo tauri build --bundles app
```

- [ ] **Step 2: Make the script record the upstream bundle paths and key metadata**

Collect:

```sh
find src-tauri/target/release/bundle/macos -type f | sort
plutil -p path/to/Info.plist
file path/to/Contents/MacOS/<exe>
```

- [ ] **Step 3: Make the script compare the upstream app against Bazel output**

First comparison targets:

```sh
test ! -e "$bazel_app/Contents/Resources/frontend"
test "$(basename "$upstream_exe")" = "$(basename "$bazel_exe")"
```

### Task 2: Make The Current Rule Fail The New Parity Test

**Files:**
- Modify: `test/validate_examples.sh`

- [ ] **Step 1: Add the parity script to validation or document it as a targeted failing check**

Run: `./test/compare_tauri_parity.sh`
Expected: FAIL because the current Bazel bundle still diverges from upstream behavior

- [ ] **Step 2: Capture the concrete mismatches**

Expected early mismatches:

```text
loose frontend files exist in Bazel bundle
bundle executable naming or plist fields may differ
resource placement may differ
```

### Task 3: Introduce Tauri-Compatible Release Asset Preparation

**Files:**
- Create: `tools/tauri_codegen_assets.py`
- Modify: `tools/BUILD.bazel`
- Modify: `private/bundle_inputs.bzl`

- [ ] **Step 1: Implement a helper that mirrors upstream release asset embedding inputs**

The tool should:

- read Tauri config
- resolve `frontend_dist`
- normalize release asset inputs deterministically
- emit generated outputs Bazel can feed into Rust compilation or bundle metadata

- [ ] **Step 2: Add a failing unit-style check for the helper on the example app**

Run: `bazel build //examples/tauri_with_vite:bundle_inputs_arm64`
Expected: FAIL until the rule consumes the helper output correctly

- [ ] **Step 3: Remove loose `frontend_dist` copying for normal release bundling**

Expected behavior after implementation:

```text
no Contents/Resources/frontend/... tree for normal release apps
```

### Task 4: Align macOS Bundle Assembly With Upstream Bundler Semantics

**Files:**
- Modify: `private/bundle_inputs.bzl`
- Modify: `private/plist.bzl`
- Modify: `private/paths.bzl`
- Modify: `private/macos_app.bzl`
- Modify: `tools/make_plist.py`
- Modify: `tools/make_manifest.py`

- [ ] **Step 1: Match executable naming and plist executable field behavior**

Ensure:

```text
Contents/MacOS/<main executable name>
CFBundleExecutable == <main executable name>
```

- [ ] **Step 2: Match resource and external binary semantics**

Ensure:

```text
resource normalization matches tauri-utils
sidecar target suffixes are stripped
frameworks and macOS custom files follow tauri-bundler layout
```

- [ ] **Step 3: Match plist generation and merge order more closely**

Verify key fields against upstream output for the example app.

### Task 5: Convert The Example Into A Real Parity Example

**Files:**
- Modify: `examples/tauri_with_vite/BUILD.bazel`
- Modify: `examples/tauri_with_vite/README.md`
- Modify: `README.md`
- Modify: `docs/testing.md`

- [ ] **Step 1: Update the example targets to represent the new semantics**

`frontend_dist` should be treated as embedding input, not loose bundle payload.

- [ ] **Step 2: Document the new contract**

Make it explicit that:

```text
release frontend assets are embedded to match normal Tauri behavior
rules_tauri still stops at an unsigned .app
```

### Task 6: Verify With Parity Evidence

**Files:**
- Modify: `test/compare_tauri_parity.sh`
- Modify: `test/validate_examples.sh`

- [ ] **Step 1: Run the smoke test**

Run: `./test/validate_examples.sh`
Expected: PASS

- [ ] **Step 2: Run the parity test**

Run: `./test/compare_tauri_parity.sh`
Expected: PASS for the checked parity dimensions

- [ ] **Step 3: Inspect the final Bazel app manually**

Run:

```sh
find -L bazel-bin/examples/tauri_with_vite/app_arm64.app -type f | sort
plutil -p bazel-bin/examples/tauri_with_vite/app_arm64.app/Contents/Info.plist
```

Expected:

```text
no loose frontend resource tree for the normal release app
key plist values align with upstream
```
