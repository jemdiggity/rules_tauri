# Remove Minimal Embedded Assets Shim Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the unused `//examples/minimal_macos:embedded_assets_rust` compatibility shim now that validation reads the generated target directly.

**Architecture:** Prove the shim still exists with a focused negative test, then delete only that root-level `genrule` and update the test to expect the label to be absent. Keep the example release path and generated embedded-assets output unchanged.

**Tech Stack:** Bazel, shell tests, example BUILD targets

---

### Task 1: Add a failing negative-label test

**Files:**
- Create: `test/api_rejects_minimal_embedded_assets_shim.sh`

- [ ] **Step 1: Write the failing shell test**

```sh
#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$repo_root"

stdout_log=$(mktemp)
stderr_log=$(mktemp)
trap 'rm -f "$stdout_log" "$stderr_log"' EXIT

if bazel query //examples/minimal_macos:embedded_assets_rust >"$stdout_log" 2>"$stderr_log"; then
  echo "expected minimal embedded assets shim to be removed" >&2
  exit 1
fi

grep -q "embedded_assets_rust" "$stderr_log"
```

- [ ] **Step 2: Run the test to verify RED**

Run: `./test/api_rejects_minimal_embedded_assets_shim.sh`
Expected: FAIL because the label still exists

### Task 2: Remove the shim

**Files:**
- Modify: `examples/minimal_macos/BUILD.bazel`

- [ ] **Step 1: Delete the root-level `genrule`**

```starlark
genrule(
    name = "embedded_assets_rust",
    srcs = ["//examples/minimal_macos/src-tauri:app_arm64_embedded_assets_rust.rs"],
    outs = ["embedded_assets_rust.rs"],
    cmd = "cp $(location //examples/minimal_macos/src-tauri:app_arm64_embedded_assets_rust.rs) $@",
)
```

- [ ] **Step 2: Run the test to verify GREEN**

Run: `./test/api_rejects_minimal_embedded_assets_shim.sh`
Expected: PASS with Bazel reporting no such target

### Task 3: Re-run example validation

**Files:**
- No additional file changes expected

- [ ] **Step 1: Re-run example validation**

Run: `./test/validate_examples.sh`
Expected: PASS

- [ ] **Step 2: Commit**

```bash
git add examples/minimal_macos/BUILD.bazel test/api_rejects_minimal_embedded_assets_shim.sh docs/superpowers/plans/2026-04-12-remove-minimal-embedded-assets-shim.md
git commit -m "example: remove minimal embedded assets shim"
```
