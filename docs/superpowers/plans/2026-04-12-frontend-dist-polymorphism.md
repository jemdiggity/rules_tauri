# Frontend Dist Polymorphism Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `tauri_application()` accept `frontend_dist` as either a directory-producing target or a file set, and internalize frontend normalization plus embedded-assets generation.

**Architecture:** Add one private frontend-normalization rule that emits a canonical directory artifact, then route `tauri_application()` and its release-context helpers through that normalized tree. Remove the explicit `embedded_assets_rust` requirement from the high-level macro and simplify examples to rely on the owned path.

**Tech Stack:** Bazel Starlark, `rules_rust`, existing Python/Rust helper tools, shell-based example validation

---

### Task 1: Add Regression Coverage For Frontend Shape Handling

**Files:**
- Modify: `test/validate_examples.sh`

- [ ] **Step 1: Add a regression assertion for the static example asset key**

Update `test/validate_examples.sh` so it builds the generated embedded-assets file for `minimal_macos` and checks for `("/index.html", ...)` in the output.

- [ ] **Step 2: Run the validation script to confirm the current baseline**

Run: `./test/validate_examples.sh`
Expected: PASS on the current branch before refactoring

- [ ] **Step 3: Commit the regression-only change if split commits are desired**

Run:
```bash
git add test/validate_examples.sh
git commit -m "test: cover static frontend asset keys"
```

### Task 2: Add Private Frontend Normalization

**Files:**
- Create: `private/frontend_dist.bzl`
- Modify: `tauri/defs.bzl`

- [ ] **Step 1: Write the private normalization rule**

Create `private/frontend_dist.bzl` with a rule that:
- accepts one target
- if the target yields a single directory artifact, returns it unchanged
- otherwise copies the target files into a declared directory with stable relative paths

- [ ] **Step 2: Expose macro-local usage in `tauri/defs.bzl`**

Load the new private helper into `tauri/defs.bzl` and thread a normalized frontend target through `tauri_application()`.

- [ ] **Step 3: Remove explicit `embedded_assets_rust` from the high-level macro path**

Update `tauri_application()` so it creates the embedded-assets file internally from the normalized frontend tree rather than requiring a caller-supplied target.

- [ ] **Step 4: Run focused builds**

Run:
```bash
bazel build //examples/minimal_macos:app_arm64 //examples/tauri_with_vite:app_arm64
```
Expected: both targets build successfully

- [ ] **Step 5: Commit the macro and helper change**

Run:
```bash
git add tauri/defs.bzl private/frontend_dist.bzl
git commit -m "feat: normalize frontend_dist in tauri_application"
```

### Task 3: Route Release Context Through The Normalized Frontend Tree

**Files:**
- Modify: `private/release_context.bzl`
- Modify: `private/upstream_context_oracle.bzl`

- [ ] **Step 1: Update frontend-sensitive helpers to use the normalized tree contract**

Ensure ACL prep and oracle/context generation consume the canonical normalized frontend directory rather than assuming callers already produced exactly one compatible output.

- [ ] **Step 2: Verify directory and file-set cases still work**

Run:
```bash
bazel build //examples/minimal_macos/src-tauri:app_arm64_lib_release_context //examples/tauri_with_vite/app/src-tauri:app_arm64_lib_release_context
```
Expected: both release-context targets build successfully

- [ ] **Step 3: Commit the release-context wiring**

Run:
```bash
git add private/release_context.bzl private/upstream_context_oracle.bzl
git commit -m "feat: route release context through normalized frontend"
```

### Task 4: Simplify Examples To Use The Owned Frontend Path

**Files:**
- Modify: `examples/minimal_macos/BUILD.bazel`
- Delete: `examples/minimal_macos/example_build.bzl`
- Modify: `examples/minimal_macos/src-tauri/BUILD.bazel`
- Modify: `examples/tauri_with_vite/app/src-tauri/BUILD.bazel`

- [ ] **Step 1: Remove example-only frontend normalization glue from `minimal_macos`**

Replace the local helper-based frontend tree construction with a plain file-set target so the example proves the new permissive input path.

- [ ] **Step 2: Remove explicit `embedded_assets_rust` wiring from both examples’ `tauri_application()` usage**

Update the examples so they rely on the macro-owned asset generation path instead of passing a separate embedded-assets target into the macro.

- [ ] **Step 3: Keep any lower-level example targets only if still needed outside `tauri_application()`**

Delete no-longer-needed example glue while preserving example readability.

- [ ] **Step 4: Run example builds**

Run:
```bash
bazel build //examples/minimal_macos:app_arm64 //examples/minimal_macos:app_x86_64 //examples/tauri_with_vite:app_arm64 //examples/tauri_with_vite:app_x86_64
```
Expected: all four builds succeed

- [ ] **Step 5: Commit the example simplification**

Run:
```bash
git add examples/minimal_macos/BUILD.bazel examples/minimal_macos/src-tauri/BUILD.bazel examples/tauri_with_vite/app/src-tauri/BUILD.bazel
git rm examples/minimal_macos/example_build.bzl
git commit -m "example: simplify frontend wiring in tauri_application examples"
```

### Task 5: Update Documentation For The Simpler Frontend Contract

**Files:**
- Modify: `README.md`
- Modify: `examples/minimal_macos/README.md`
- Modify: `examples/tauri_with_vite/README.md`

- [ ] **Step 1: Document the new `frontend_dist` semantics**

Explain that `tauri_application()` accepts either a directory target or a file set and owns normalization plus embedded-assets generation internally.

- [ ] **Step 2: Remove docs that imply consumers must always precompute `embedded_assets_rust` for the high-level path**

Keep lower-level escape hatches documented separately if still supported.

- [ ] **Step 3: Commit the docs update**

Run:
```bash
git add README.md examples/minimal_macos/README.md examples/tauri_with_vite/README.md
git commit -m "docs: simplify frontend_dist contract"
```

### Task 6: Full Verification

**Files:**
- Test: `test/validate_examples.sh`

- [ ] **Step 1: Run full example validation**

Run:
```bash
./test/validate_examples.sh
```
Expected: `rules_tauri example validation passed`

- [ ] **Step 2: Launch both example apps**

Run:
```bash
open bazel-bin/examples/minimal_macos/src-tauri/app_arm64.app
open bazel-bin/examples/tauri_with_vite/app/src-tauri/app_arm64.app
```
Expected: both apps launch successfully without frontend asset lookup failures

- [ ] **Step 3: Inspect worktree and summarize final API delta**

Run:
```bash
git status --short
git log --oneline -n 5
```
Expected: only intended changes remain

- [ ] **Step 4: Commit any final verification-only adjustments**

Run:
```bash
git add -A
git commit -m "test: finalize frontend_dist polymorphism verification"
```
