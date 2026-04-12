# ACL Name Normalization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Preserve authored plugin capability prefixes like `opener:*` in Bazel ACL staging and align dependency permission metadata reconstruction with upstream Tauri so release validation resolves plain plugin names correctly.

**Architecture:** Add a focused regression against the real `tauri_with_vite` example that inspects the staged capability file, ACL manifests, and resolved capabilities output. Remove the staged JSON rewrite, then fix `tauri_acl_prep`'s synthetic permission-file env names so `tauri_utils::acl::build::read_permissions()` produces upstream plugin keys like `opener` instead of `plugin-opener`.

**Tech Stack:** Rust helper tool, Bazel shell validation, real example fixture

---

### Task 1: Add a failing regression test

**Files:**
- Create: `test/validate_acl_name_normalization.sh`

- [ ] **Step 1: Write the failing shell test**

```sh
#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$repo_root"

path_for() {
  bazel cquery --output=starlark --starlark:expr='target.files.to_list()[0].path' "$1"
}

bazel build --action_env=PATH \
  //examples/tauri_with_vite/app/src-tauri:_app_arm64_lib_release_context_acl_prep

acl_dir="$repo_root/$(path_for //examples/tauri_with_vite/app/src-tauri:_app_arm64_lib_release_context_acl_prep)"
staged_capability="$acl_dir/_staged_config/capabilities/default.json"
resolved_capabilities="$acl_dir/capabilities.json"

grep -q '"opener:default"' "$staged_capability"
! grep -q '"plugin-opener:default"' "$staged_capability"
grep -q '"plugin-opener:default"' "$resolved_capabilities"
```

- [ ] **Step 2: Run the test to verify RED**

Run: `./test/validate_acl_name_normalization.sh`
Expected: FAIL because Bazel ACL prep currently either rewrites the staged file or reconstructs plugin metadata with the wrong manifest key

### Task 2: Remove staged capability mutation and fix plugin env reconstruction

**Files:**
- Modify: `tools/tauri_acl_prep/src/main.rs`

- [ ] **Step 1: Delete the capability content rewrite**

```rust
        if source_path.extension().and_then(|value| value.to_str()) == Some("json") {
            copy_file(&source_path, &destination_path)?;
            continue;
        }
```

- [ ] **Step 2: Make `permission_env_var()` mirror upstream plugin naming**

```rust
    if let Some(plugin) = file_name.strip_suffix("-permission-files") {
        return Ok(format!(
            "DEP_TAURI_{}_PERMISSION_FILES_PATH",
            plugin.replace('-', "_").to_ascii_uppercase()
        ));
    }
```

- [ ] **Step 3: Run the focused regression**

Run: `./test/validate_acl_name_normalization.sh`
Expected: PASS

### Task 3: Verify example build path still works

**Files:**
- No additional file changes expected

- [ ] **Step 1: Re-run example validation**

Run: `./test/validate_examples.sh`
Expected: PASS

- [ ] **Step 2: Commit**

```bash
git add tools/tauri_acl_prep/src/main.rs test/validate_acl_name_normalization.sh docs/superpowers/plans/2026-04-13-acl-name-normalization.md
git commit -m "fix: preserve authored ACL capability names"
```
