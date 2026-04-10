# Rules Rust Codegen Fixture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a minimal Bazel fixture that proves Tauri asset embedding works under `rules_rust` before changing the real example again.

**Architecture:** Keep `examples/tauri_with_vite` on the last known-good wrapper-based build. Add a separate `test/fixtures/tauri_codegen` package with a tiny Tauri crate, a baked frontend fixture, and one focused validation script that checks the built probe binary for embedded asset markers. Only once that fixture passes should its wiring be promoted into the real example.

**Tech Stack:** Bazel, `rules_rust`, Tauri 2, Cargo build scripts, shell validation

---

### Task 1: Create the failing fixture target

**Files:**
- Create: `test/fixtures/tauri_codegen/BUILD.bazel`
- Create: `test/fixtures/tauri_codegen/src-tauri/Cargo.toml`
- Create: `test/fixtures/tauri_codegen/src-tauri/build.rs`
- Create: `test/fixtures/tauri_codegen/src-tauri/src/main.rs`
- Create: `test/fixtures/tauri_codegen/src-tauri/src/lib.rs`
- Create: `test/fixtures/tauri_codegen/src-tauri/tauri.conf.json`
- Create: `test/fixtures/tauri_codegen/src-tauri/capabilities/default.json`
- Create: `test/fixtures/tauri_codegen/dist/index.html`
- Create: `test/fixtures/tauri_codegen/dist/assets/index-fixture.js`
- Create: `test/fixtures/tauri_codegen/dist/assets/index-fixture.css`
- Create: `test/fixtures/tauri_codegen/dist/vite.svg`
- Test: `test/validate_rules_rust_codegen_fixture.sh`

- [ ] **Step 1: Keep the existing red test as the target contract**

Run: `sh test/validate_rules_rust_codegen_fixture.sh`
Expected: FAIL with `no such package 'test/fixtures/tauri_codegen'`

- [ ] **Step 2: Add the minimal fixture package and files**

Create a tiny Tauri app with:

```toml
# test/fixtures/tauri_codegen/src-tauri/Cargo.toml
[package]
name = "tauri-codegen-fixture"
version = "0.1.0"
edition = "2021"

[lib]
name = "tauri_codegen_fixture_lib"
crate-type = ["rlib"]

[build-dependencies]
tauri-build = { version = "2" }

[dependencies]
tauri = { version = "2", features = [] }
serde = { version = "1", features = ["derive"] }
serde_json = "1"
```

```rust
// test/fixtures/tauri_codegen/src-tauri/build.rs
fn main() {
    tauri_build::build()
}
```

```rust
// test/fixtures/tauri_codegen/src-tauri/src/lib.rs
pub fn run() {
    let _ = tauri::generate_context!();
}
```

```rust
// test/fixtures/tauri_codegen/src-tauri/src/main.rs
fn main() {
    tauri_codegen_fixture_lib::run();
}
```

The config should point at `../dist`, and the dist fixture should include `index.html`, one JS asset, one CSS asset, and `vite.svg`.

- [ ] **Step 3: Add the minimal Bazel target skeleton**

Create `test/fixtures/tauri_codegen/BUILD.bazel` with a placeholder `codegen_probe` target shape that can later be upgraded to `rules_rust`:

```starlark
package(default_visibility = ["//visibility:public"])

filegroup(
    name = "fixture_srcs",
    srcs = glob(["src-tauri/**", "dist/**"]),
)
```

Leave the package in a state where the original missing-package failure is replaced by a more specific missing-target or build failure.

- [ ] **Step 4: Run the red test again**

Run: `sh test/validate_rules_rust_codegen_fixture.sh`
Expected: FAIL for a more specific reason than missing package, such as missing target or failed build of `codegen_probe`

- [ ] **Step 5: Commit**

```bash
git add test/validate_rules_rust_codegen_fixture.sh test/fixtures/tauri_codegen docs/superpowers/plans/2026-04-10-rules-rust-codegen-fixture.md
git commit -m "test: add tauri codegen fixture scaffold"
```

### Task 2: Make the fixture pass with the current wrapper path

**Files:**
- Modify: `test/fixtures/tauri_codegen/BUILD.bazel`
- Create: `tools/build_tauri_codegen_fixture_binary.sh`
- Modify: `tools/BUILD.bazel`
- Test: `test/validate_rules_rust_codegen_fixture.sh`

- [ ] **Step 1: Add a wrapper-built probe binary target**

Add a `genrule` that builds the fixture binary using the same proven Cargo wrapper pattern as the real example.

- [ ] **Step 2: Add the helper script**

Create a small script that:
- copies `test/fixtures/tauri_codegen/src-tauri`
- copies `test/fixtures/tauri_codegen/dist`
- runs `cargo build --release --features tauri/custom-protocol --bins`
- copies the resulting probe binary to the declared Bazel output

- [ ] **Step 3: Run the fixture validation**

Run: `sh test/validate_rules_rust_codegen_fixture.sh`
Expected: PASS with `rules_rust tauri codegen fixture passed`

- [ ] **Step 4: Verify the binary contains the asset markers directly**

Run: `strings bazel-bin/test/fixtures/tauri_codegen/codegen_probe | grep '/assets/index-'`
Expected: one matching asset path

- [ ] **Step 5: Commit**

```bash
git add test/fixtures/tauri_codegen tools/build_tauri_codegen_fixture_binary.sh tools/BUILD.bazel
git commit -m "test: validate tauri codegen fixture with cargo wrapper"
```

### Task 3: Swap only the fixture to `rules_rust`

**Files:**
- Modify: `MODULE.bazel`
- Modify: `test/fixtures/tauri_codegen/BUILD.bazel`
- Add or modify only fixture-local helper files if strictly needed
- Test: `test/validate_rules_rust_codegen_fixture.sh`

- [ ] **Step 1: Add `rules_rust` and minimal crate-universe wiring**

Introduce only the dependencies needed for the fixture crate and keep the real example untouched.

- [ ] **Step 2: Replace the wrapper-built fixture with `cargo_build_script` + `rust_binary`**

The fixture should build under Bazel-native Rust while still consuming the baked `dist` fixture.

- [ ] **Step 3: Run the fixture validation**

Run: `sh test/validate_rules_rust_codegen_fixture.sh`
Expected: PASS

- [ ] **Step 4: If it fails, inspect the generated Tauri context before changing anything else**

Run commands like:

```bash
find "$(bazel info output_base)" -name 'tauri-build-context.rs' -print
```

Expected: enough evidence to explain whether assets were embedded or not

- [ ] **Step 5: Commit**

```bash
git add MODULE.bazel test/fixtures/tauri_codegen
git commit -m "feat: build tauri codegen fixture with rules_rust"
```

### Task 4: Promote the proven fixture wiring into the real example

**Files:**
- Modify: `examples/tauri_with_vite/BUILD.bazel`
- Modify: any new Bazel helper files only if the fixture proved they are required
- Modify: `test/validate_examples.sh`
- Modify: `test/compare_tauri_parity.sh`

- [ ] **Step 1: Keep the fixture green while changing the real example**

Run: `sh test/validate_rules_rust_codegen_fixture.sh`
Expected: PASS before touching the real example

- [ ] **Step 2: Apply only the already-proven `rules_rust` wiring to `examples/tauri_with_vite`**

Do not invent new behavior during this step.

- [ ] **Step 3: Re-run example validation**

Run: `./test/validate_examples.sh`
Expected: PASS

- [ ] **Step 4: Re-run parity validation**

Run: `./test/compare_tauri_parity.sh`
Expected: PASS

- [ ] **Step 5: Launch the real example manually**

Run: `open bazel-bin/examples/tauri_with_vite/app_arm64.app`
Expected: non-blank window

- [ ] **Step 6: Commit**

```bash
git add examples/tauri_with_vite test
git commit -m "feat: build tauri example with rules_rust"
```
