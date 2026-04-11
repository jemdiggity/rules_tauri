# Remove Real Example Helper Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove `upstream_build.rs` and `upstream_build_script` from the real `examples/tauri_with_vite` Bazel build path while keeping the fixture as the upstream oracle and preserving example parity.

**Architecture:** Keep the fixture on the narrower helper-based oracle seam, but make the real example fully Bazel-owned at the full-context boundary. The real example `build.rs` remains a thin staging layer, but it reads only Bazel-generated artifacts and emits the build-script contract directly instead of copying helper out-dir contents.

**Tech Stack:** Bazel/Starlark, `rules_rust`, Rust build scripts, existing Tauri context/ACL exec tools, shell/Python verification scripts

---

## File Responsibilities

- Modify: `examples/tauri_with_vite/app/src-tauri/BUILD.bazel`
  Remove helper targets from the real example graph and connect the example to Bazel-owned context/ACL outputs only.

- Modify: `examples/tauri_with_vite/app/src-tauri/build.rs`
  Stop reading `RULES_TAURI_BAZEL_UPSTREAM_OUT_DIR`; stage only Bazel-generated artifacts into `OUT_DIR`; preserve the cargo fallback path used by parity testing.

- Delete: `examples/tauri_with_vite/app/src-tauri/upstream_build.rs`
  Remove the real-example helper once the Bazel-owned path is green.

- Modify: `private/upstream_context_oracle.bzl`
  Keep fixture-specific helper/oracle behavior, but stop forcing the real example to depend on the helper target.

- Modify: `test/validate_examples.sh`
  Replace helper-vs-active sidecar assertions with explicit assertions for the Bazel-owned real-example contract.

- Modify: `test/compare_tauri_parity.sh`
  Keep the app-level cargo-vs-Bazel parity oracle green after helper removal.

### Task 1: Lock the Real-Example Helper Removal Seam

**Files:**
- Modify: `test/validate_examples.sh`
- Test: `test/validate_examples.sh`

- [ ] **Step 1: Write the failing real-example validation change**

Edit `test/validate_examples.sh` so it no longer builds `//examples/tauri_with_vite/app/src-tauri:upstream_build_script` and no longer reads `upstream_build_script.flags`, `upstream_build_script.env`, or `upstream_build_script.depenv`.

Replace those assertions with explicit checks that the active Bazel-owned build script still emits the contract files:

```sh
test -f "$build_flags"
test -f "$build_env"
test -f "$build_depenv"
grep -q "RULES_TAURI_BAZEL_FULL_CONTEXT" "$build_env"
grep -q "cargo:rustc-env=TAURI_ENV_TARGET_TRIPLE=" "$build_flags"
grep -q "cargo:PERMISSION_FILES_PATH=" "$build_flags"
grep -q "TAURI_ANDROID_PACKAGE_NAME_APP_NAME=tauri_with_vite" "$build_flags"
grep -q "TAURI_ANDROID_PACKAGE_NAME_PREFIX=com_example" "$build_flags"
grep -q "build_script.out_dir/app-manifest/__app__-permission-files" "$build_flags"
```

- [ ] **Step 2: Run the validation to verify it fails for the current helper-based graph**

Run: `./test/validate_examples.sh`

Expected: `FAIL` because the real example build still depends on `upstream_build_script` and the script still references that target.

- [ ] **Step 3: Commit the red guardrail**

```bash
git add test/validate_examples.sh
git commit -m "test: lock helper-free real example contract"
```

### Task 2: Remove the Real Example Helper from the Build Graph

**Files:**
- Modify: `examples/tauri_with_vite/app/src-tauri/BUILD.bazel`
- Modify: `private/upstream_context_oracle.bzl`
- Delete: `examples/tauri_with_vite/app/src-tauri/upstream_build.rs`
- Test: `bazel build //examples/tauri_with_vite/app/src-tauri:build_script`

- [ ] **Step 1: Make the real example stop exporting helper sources**

Update `examples/tauri_with_vite/app/src-tauri/BUILD.bazel` so `cargo_srcs` removes `"upstream_build.rs"`.

- [ ] **Step 2: Stop the macro from forcing a real-example helper target**

Update `private/upstream_context_oracle.bzl` so fixture-only helper/oracle behavior stays behind `_is_acl_fixture(rundir)`, while the real example’s `full_context_rust` is generated directly from Bazel-owned ACL/context tooling without `cargo_build_script(name = upstream_name, ...)`.

- [ ] **Step 3: Remove helper references from the real example targets**

Update `examples/tauri_with_vite/app/src-tauri/BUILD.bazel` so the real `build_script` target drops:

```python
":upstream_build_script",
"RULES_TAURI_BAZEL_UPSTREAM_OUT_DIR": "$(location :upstream_build_script)",
```

and `tauri_upstream_context_oracle(...)` is either replaced by direct targets or updated inputs that do not materialize `upstream_build_script` for the real example.

- [ ] **Step 4: Delete the unused real-example helper source**

```bash
git rm -f examples/tauri_with_vite/app/src-tauri/upstream_build.rs
```

- [ ] **Step 5: Run the focused build to verify the helper-free graph passes**

Run: `bazel build --action_env=PATH //examples/tauri_with_vite/app/src-tauri:build_script`

Expected: `PASS`

- [ ] **Step 6: Commit the build-graph cutover**

```bash
git add examples/tauri_with_vite/app/src-tauri/BUILD.bazel private/upstream_context_oracle.bzl
git commit -m "feat: remove real example helper build script"
```

### Task 3: Remove Helper Coupling from the Real Example Build Script

**Files:**
- Modify: `examples/tauri_with_vite/app/src-tauri/build.rs`
- Test: `bazel build //examples/tauri_with_vite/app/src-tauri:tauri_with_vite_bin`

- [ ] **Step 1: Write the failing build-script change**

Update `examples/tauri_with_vite/app/src-tauri/build.rs` so the Bazel path no longer reads `RULES_TAURI_BAZEL_UPSTREAM_OUT_DIR`, no longer calls `copy_upstream_out_dir`, and instead only:

```rust
println!("cargo:rerun-if-env-changed=RULES_TAURI_BAZEL_FULL_CONTEXT");
println!("cargo:rerun-if-changed={full_context_path}");

let out_dir = PathBuf::from(std::env::var("OUT_DIR").expect("missing OUT_DIR"));
let out_path = out_dir.join("tauri-build-context.rs");
fs::copy(&full_context_path, &out_path).unwrap_or_else(|error| {
    panic!(
        "failed to copy {} to {}: {error}",
        full_context_path,
        out_path.display()
    )
});

emit_upstream_contract(&out_dir);
```

Keep the existing cargo fallback branch:

```rust
if std::env::var_os("RULES_TAURI_BAZEL_FULL_CONTEXT").is_none() {
    let attributes = tauri_build::Attributes::new().codegen(tauri_build::CodegenContext::new());
    tauri_build::try_build(attributes).expect("failed to generate Tauri build context");
    return;
}
```

- [ ] **Step 2: Run the focused binary build to verify the first failure**

Run: `bazel build --action_env=PATH //examples/tauri_with_vite/app/src-tauri:tauri_with_vite_bin`

Expected: either `FAIL` because the contract no longer has all required Bazel-generated files staged, or `PASS` if the helper was already redundant.

- [ ] **Step 3: Add only the missing Bazel-owned staging needed to restore the build**

If Step 2 fails, update only the minimal staging logic in `build.rs` or `BUILD.bazel` needed to restore the binary build, without reintroducing helper coupling.

- [ ] **Step 4: Run the focused binary build to verify it passes**

Run: `bazel build --action_env=PATH //examples/tauri_with_vite/app/src-tauri:tauri_with_vite_bin`

Expected: `PASS`

- [ ] **Step 5: Commit the helper-free build-script change**

```bash
git add examples/tauri_with_vite/app/src-tauri/build.rs
git commit -m "feat: make real example build script helper-free"
```

### Task 4: Keep App-Level Parity Green

**Files:**
- Modify: `test/compare_tauri_parity.sh` only if needed
- Test: `test/compare_tauri_parity.sh`

- [ ] **Step 1: Run the parity oracle on the helper-free example**

Run: `./test/compare_tauri_parity.sh`

Expected: `PASS`

- [ ] **Step 2: If parity fails, make the smallest compatibility fix**

Adjust only the Bazel-owned real-example path to preserve cargo-vs-Bazel app parity. Do not broaden public API or reintroduce `upstream_build.rs`.

- [ ] **Step 3: Re-run parity to verify it passes**

Run: `./test/compare_tauri_parity.sh`

Expected: `PASS`

- [ ] **Step 4: Commit any parity-only fix**

```bash
git add examples/tauri_with_vite/app/src-tauri/BUILD.bazel examples/tauri_with_vite/app/src-tauri/build.rs test/compare_tauri_parity.sh
git commit -m "test: keep real example parity after helper removal"
```

### Task 5: Full Verification and Cleanup

**Files:**
- Modify: `test/validate_examples.sh` if follow-up assertions are needed
- Test:
  - `./test/validate_rules_rust_codegen_fixture.sh`
  - `./test/compare_full_codegen_context.sh`
  - `./test/compare_context_build_config.sh`
  - `./test/validate_examples.sh`
  - `./test/compare_tauri_parity.sh`

- [ ] **Step 1: Run the full verification matrix**

Run:

```bash
./test/validate_rules_rust_codegen_fixture.sh
./test/compare_full_codegen_context.sh
./test/compare_context_build_config.sh
./test/validate_examples.sh
./test/compare_tauri_parity.sh
```

Expected: all commands `PASS`

- [ ] **Step 2: Confirm the helper is gone only from the real example**

Run:

```bash
rg -n "upstream_build_script|upstream_build\\.rs" \
  examples/tauri_with_vite \
  test/fixtures/tauri_codegen \
  test
```

Expected:
- no matches under `examples/tauri_with_vite`
- fixture references still remain under `test/fixtures/tauri_codegen`

- [ ] **Step 3: Commit any final verification-only adjustments**

```bash
git add -A
git commit -m "chore: finish real example helper removal"
```
