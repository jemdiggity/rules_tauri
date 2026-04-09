# Tauri With Vite Example Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the placeholder `examples/tauri_with_vite` example with a real vendored Tauri 2 + Vue + Vite app that `rules_tauri` packages into an unsigned macOS `.app`.

**Architecture:** Vendor a generated Tauri Vue/Vite project into `examples/tauri_with_vite`, check in the produced frontend and macOS binary fixtures, and keep Bazel responsible only for packaging those inputs into `.app` bundles. Extend validation and docs so the example is part of the repository contract.

**Tech Stack:** Bazel, Starlark, Tauri 2, Vue, Vite, Rust, shell validation

---

### Task 1: Inspect The Current Template And Fixture Feasibility

**Files:**
- Modify: `docs/superpowers/specs/2026-04-09-tauri-with-vite-design.md`
- Modify: `docs/superpowers/plans/2026-04-09-tauri-with-vite.md`

- [ ] **Step 1: Scaffold the upstream template in a temporary directory**

Run: `tmpdir="$(mktemp -d)" && cd "$tmpdir" && bun create tauri-app@latest --template vue --manager bun tauri-with-vite`
Expected: a generated Tauri Vue/Vite app appears under the temp directory

- [ ] **Step 2: Inspect the generated file layout**

Run: `find "$tmpdir/tauri-with-vite" -maxdepth 3 -type f | sort`
Expected: Vue frontend files and `src-tauri` Rust files are present

- [ ] **Step 3: Decide which generated outputs to vendor as fixtures**

Run: `cd "$tmpdir/tauri-with-vite" && sed -n '1,220p' package.json && sed -n '1,220p' src-tauri/Cargo.toml`
Expected: enough context to map generated outputs onto `rules_tauri` inputs

### Task 2: Write The Example Validation First

**Files:**
- Modify: `test/validate_examples.sh`

- [ ] **Step 1: Add failing checks for the new example bundle outputs**

Add checks for:

```sh
  //examples/tauri_with_vite:app_arm64 \
  //examples/tauri_with_vite:app_x86_64
```

and bundle assertions such as:

```sh
vite_arm64_app="$repo_root/bazel-bin/examples/tauri_with_vite/app_arm64.app"
test -f "$vite_arm64_app/Contents/Info.plist"
test -f "$vite_arm64_app/Contents/MacOS/tauri-with-vite"
test -f "$vite_arm64_app/Contents/Resources/AppIcon.icns"
```

- [ ] **Step 2: Run validation to verify it fails for the missing example**

Run: `./test/validate_examples.sh`
Expected: FAIL because `//examples/tauri_with_vite:*` targets do not exist yet

### Task 3: Vendor The Generated Example Sources And Fixtures

**Files:**
- Create or modify files under: `examples/tauri_with_vite/**`

- [ ] **Step 1: Copy the generated source tree into the example directory**

Source paths should include the Vue/Vite frontend and `src-tauri` tree from the scaffolded app.

- [ ] **Step 2: Build the frontend fixture**

Run: `cd examples/tauri_with_vite && bun install && bun run build`
Expected: Vite `dist/` output is produced for vendoring

- [ ] **Step 3: Build release binaries for macOS fixture inputs**

Run: `cd examples/tauri_with_vite/src-tauri && cargo build --release --target aarch64-apple-darwin`
Expected: arm64 Mach-O binary is produced

Run: `cd examples/tauri_with_vite/src-tauri && cargo build --release --target x86_64-apple-darwin`
Expected: x86_64 Mach-O binary is produced

- [ ] **Step 4: Place vendored fixtures in stable example-owned paths**

Expected fixture layout:

```text
examples/tauri_with_vite/src/frontend_dist/...
examples/tauri_with_vite/src/bin/tauri-with-vite-aarch64-apple-darwin
examples/tauri_with_vite/src/bin/tauri-with-vite-x86_64-apple-darwin
examples/tauri_with_vite/src/icons/AppIcon.icns
examples/tauri_with_vite/src/tauri.conf.json
```

### Task 4: Define Bazel Targets For The Real Example

**Files:**
- Modify: `examples/tauri_with_vite/BUILD.bazel`
- Modify: `examples/tauri_with_vite/README.md`

- [ ] **Step 1: Add `tauri_bundle_inputs` and `tauri_macos_app` targets**

Model them after `examples/minimal_macos/BUILD.bazel`, but point to the vendored frontend and binary fixtures.

- [ ] **Step 2: Expose `app_arm64`, `app_x86_64`, and optional convenience aliases**

Expected target names:

```starlark
tauri_macos_app(name = "app_arm64", ...)
tauri_macos_app(name = "app_x86_64", ...)
```

- [ ] **Step 3: Document the example clearly**

Describe that it is based on `create tauri-app`, but Bazel packages checked-in outputs to preserve the repository contract.

### Task 5: Verify End-To-End

**Files:**
- Modify: `README.md`
- Modify: `docs/testing.md`

- [ ] **Step 1: Run the full example validation**

Run: `./test/validate_examples.sh`
Expected: PASS with both examples built and validated

- [ ] **Step 2: Inspect the produced `tauri_with_vite` bundle**

Run: `find -L bazel-bin/examples/tauri_with_vite/app_arm64.app -maxdepth 3 -type f | sort`
Expected: real app bundle contents including Mach-O executable and frontend resources

- [ ] **Step 3: Update top-level docs**

Document that `tauri_with_vite` is now an implemented example and part of validation.
