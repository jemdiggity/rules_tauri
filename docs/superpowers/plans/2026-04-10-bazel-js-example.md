# Bazel-Managed JS Example Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace host-`bun` frontend building in `examples/tauri_with_vite` with a Bazel-managed JS toolchain while keeping the realistic Tauri example working, using pnpm as the example's lockfile source of truth.

**Architecture:** Add a Bazel JS ruleset and lockfile-driven dependency ingestion for the example app, expose a Bazel-built `dist` target from the vendored app, and keep `rules_rust` and `rules_tauri` consuming that output through the existing example graph.

**Tech Stack:** Bazel, Bzlmod, Bazel JS rules, Vite, Vue, `rules_rust`, Tauri 2

---

### Task 1: Add Bazel JS Toolchain Wiring

**Files:**
- Modify: `MODULE.bazel`
- Test: `bazel query //examples/tauri_with_vite/app:dist`

- [ ] **Step 1: Add the Bazel JS module dependencies**

Update `MODULE.bazel` to add the selected Bazel JS ruleset and any required toolchain/module extension setup for a pinned Node runtime.

- [ ] **Step 2: Ingest the example app lockfile**

Wire `examples/tauri_with_vite/app/package.json` and `examples/tauri_with_vite/app/pnpm-lock.yaml` into the chosen JS ruleset so Bazel can resolve the example's JS dependencies without host `bun`.

- [ ] **Step 3: Run query to verify the JS repository wiring loads**

Run: `bazel query //examples/tauri_with_vite/app:dist`
Expected: target resolves without host-tool discovery errors

- [ ] **Step 4: Commit**

```bash
git add MODULE.bazel
git commit -m "build: add bazel js toolchain for example app"
```

### Task 2: Replace the Frontend Wrapper with Bazel JS Rules

**Files:**
- Modify: `examples/tauri_with_vite/app/BUILD.bazel`
- Modify: `examples/tauri_with_vite/example_build.bzl`
- Delete: `tools/build_tauri_example_frontend.sh`
- Delete: `tools/extensions.bzl`
- Modify: `tools/BUILD.bazel`
- Test: `bazel build //examples/tauri_with_vite/app:dist`

- [ ] **Step 1: Write the failing build expectation**

Confirm the current frontend target still depends on host `bun` by checking the existing build files and noting the wrapper usage.

- [ ] **Step 2: Replace `example_frontend_dist` with Bazel JS build targets**

Implement `//examples/tauri_with_vite/app:dist` using the chosen Bazel JS rules so it runs Vite from Bazel-managed dependencies.

- [ ] **Step 3: Remove the host-tool wrapper path**

Delete the frontend wrapper-specific rule machinery from `examples/tauri_with_vite/example_build.bzl` and remove unneeded tool exports/files.

- [ ] **Step 4: Run the frontend build**

Run: `bazel build //examples/tauri_with_vite/app:dist`
Expected: PASS, producing a Bazel output tree for the Vite build without host `bun`

- [ ] **Step 5: Commit**

```bash
git add examples/tauri_with_vite/app/BUILD.bazel examples/tauri_with_vite/example_build.bzl tools/BUILD.bazel
git rm -f tools/build_tauri_example_frontend.sh tools/extensions.bzl
git commit -m "build: run example vite build with bazel js rules"
```

### Task 3: Reconnect the Real Example to the New Frontend Target

**Files:**
- Modify: `examples/tauri_with_vite/BUILD.bazel`
- Test: `bazel build //examples/tauri_with_vite:app_arm64`

- [ ] **Step 1: Keep the example graph pointed at the Bazel-built `dist`**

Update `examples/tauri_with_vite/BUILD.bazel` only if needed so both bundle inputs and Rust build inputs still consume `//examples/tauri_with_vite/app:dist`.

- [ ] **Step 2: Build the realistic example**

Run: `bazel build //examples/tauri_with_vite:app_arm64`
Expected: PASS

- [ ] **Step 3: Verify embedded assets are still present**

Run: `strings bazel-bin/examples/tauri_with_vite/app_arm64.app/Contents/MacOS/tauri-with-vite | rg '/assets/index-|/vite.svg'`
Expected: both asset markers present

- [ ] **Step 4: Commit**

```bash
git add examples/tauri_with_vite/BUILD.bazel
git commit -m "build: connect tauri example to bazel-managed dist"
```

### Task 4: Update Docs and Verification Wording

**Files:**
- Modify: `README.md`
- Modify: `docs/testing.md`
- Modify: `examples/tauri_with_vite/README.md`
- Test: `rg -n "bun|host bun|frontend wrapper" README.md docs/testing.md examples/tauri_with_vite/README.md`

- [ ] **Step 1: Update repo docs**

Revise wording so the realistic example is described as Bazel-managed on both Rust and JS sides.

- [ ] **Step 2: Confirm docs do not describe the removed host-tool path**

Run: `rg -n "host bun|build_tauri_example_frontend|rules_tauri_host_bun" README.md docs/testing.md examples/tauri_with_vite/README.md examples/tauri_with_vite/example_build.bzl`
Expected: no stale references

- [ ] **Step 3: Commit**

```bash
git add README.md docs/testing.md examples/tauri_with_vite/README.md
git commit -m "docs: describe bazel-managed frontend example build"
```

### Task 5: Run Full Verification

**Files:**
- Test: `test/validate_examples.sh`
- Test: `test/validate_rules_rust_codegen_fixture.sh`
- Test: `test/compare_tauri_parity.sh`

- [ ] **Step 1: Run example validation**

Run: `./test/validate_examples.sh`
Expected: `rules_tauri example validation passed`

- [ ] **Step 2: Run the focused Tauri codegen fixture**

Run: `./test/validate_rules_rust_codegen_fixture.sh`
Expected: `rules_rust tauri codegen fixture passed`

- [ ] **Step 3: Run upstream parity comparison**

Run: `./test/compare_tauri_parity.sh`
Expected: `tauri parity comparison passed`

- [ ] **Step 4: Confirm host `bun` is gone from the normal example build path**

Run: `rg -n "rules_tauri_host_bun|build_tauri_example_frontend|command -v bun" MODULE.bazel examples/tauri_with_vite tools`
Expected: no matches in the normal example build path

- [ ] **Step 5: Commit**

```bash
git add .
git commit -m "test: verify bazel-managed js example build"
```
