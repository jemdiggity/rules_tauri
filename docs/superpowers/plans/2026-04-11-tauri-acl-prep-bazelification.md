# Tauri ACL Prep Bazelification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the remaining Tauri ACL-preparation side effects with Bazel-owned logic, starting with the codegen fixture, while preserving final generated context behavior.

**Architecture:** Keep `rules_tauri` on the current wrapper-based baseline and split the next cut into two seams: ACL preparation and context codegen. First, add explicit fixture oracle tests for `acl-manifests.json` and `capabilities.json`; then implement a Bazel exec tool that reproduces those files from the fixture inputs; only after those files compare cleanly should the fixture stop relying on `upstream_build_script` for ACL side effects.

**Tech Stack:** Bazel/Starlark, `rules_rust`, Python test helpers, upstream Tauri ACL/codegen crates as oracle references.

---

### Task 1: Add ACL Oracle Comparisons

**Files:**
- Create: `test/compare_acl_manifests.sh`
- Create: `test/compare_capabilities_json.sh`
- Modify: `test/fixtures/tauri_codegen/src-tauri/BUILD.bazel`

- [ ] **Step 1: Write the failing ACL-manifests oracle comparison**

```sh
#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
fixture_src_tauri="$repo_root/test/fixtures/tauri_codegen/src-tauri"
fixture_dist="$repo_root/test/fixtures/tauri_codegen/dist"
cd "$repo_root"

write_oracle_build_rs() {
    cat >"$1" <<'EOF'
fn main() {
    let attributes = tauri_build::Attributes::new().codegen(tauri_build::CodegenContext::new());
    tauri_build::try_build(attributes).expect("failed to generate Tauri build context");
}
EOF
}

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

oracle_root="$tmpdir/oracle"
mkdir -p "$oracle_root"
cp -R "$fixture_src_tauri" "$oracle_root/src-tauri"
cp -R "$fixture_dist" "$oracle_root/dist"
write_oracle_build_rs "$oracle_root/src-tauri/build.rs"

(
    cd "$oracle_root/src-tauri"
    CARGO_TARGET_DIR="$tmpdir/target" cargo build --quiet >/dev/null
)

oracle_acl=$(find "$tmpdir/target/debug/build" -path '*/out/acl-manifests.json' -print | head -n1)
test -n "$oracle_acl"

bazel build --action_env=PATH //test/fixtures/tauri_codegen:codegen_probe >/dev/null
bazel_acl="$repo_root/bazel-bin/test/fixtures/tauri_codegen/src-tauri/build_script.out_dir/acl-manifests.json"

python3 - "$oracle_acl" "$bazel_acl" <<'PY'
import json
import pathlib
import sys

oracle = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
bazel = json.loads(pathlib.Path(sys.argv[2]).read_text(encoding="utf-8"))
if oracle != bazel:
    raise SystemExit(
        "acl-manifests comparison failed\n"
        f"expected: {oracle!r}\n"
        f"actual:   {bazel!r}"
    )
PY

echo "acl manifests comparison passed"
```

- [ ] **Step 2: Write the failing capabilities oracle comparison**

```sh
#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
fixture_src_tauri="$repo_root/test/fixtures/tauri_codegen/src-tauri"
fixture_dist="$repo_root/test/fixtures/tauri_codegen/dist"
cd "$repo_root"

write_oracle_build_rs() {
    cat >"$1" <<'EOF'
fn main() {
    let attributes = tauri_build::Attributes::new().codegen(tauri_build::CodegenContext::new());
    tauri_build::try_build(attributes).expect("failed to generate Tauri build context");
}
EOF
}

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

oracle_root="$tmpdir/oracle"
mkdir -p "$oracle_root"
cp -R "$fixture_src_tauri" "$oracle_root/src-tauri"
cp -R "$fixture_dist" "$oracle_root/dist"
write_oracle_build_rs "$oracle_root/src-tauri/build.rs"

(
    cd "$oracle_root/src-tauri"
    CARGO_TARGET_DIR="$tmpdir/target" cargo build --quiet >/dev/null
)

oracle_caps=$(find "$tmpdir/target/debug/build" -path '*/out/capabilities.json' -print | head -n1)
test -n "$oracle_caps"

bazel build --action_env=PATH //test/fixtures/tauri_codegen:codegen_probe >/dev/null
bazel_caps="$repo_root/bazel-bin/test/fixtures/tauri_codegen/src-tauri/build_script.out_dir/capabilities.json"

python3 - "$oracle_caps" "$bazel_caps" <<'PY'
import json
import pathlib
import sys

oracle = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
bazel = json.loads(pathlib.Path(sys.argv[2]).read_text(encoding="utf-8"))
if oracle != bazel:
    raise SystemExit(
        "capabilities comparison failed\n"
        f"expected: {oracle!r}\n"
        f"actual:   {bazel!r}"
    )
PY

echo "capabilities comparison passed"
```

- [ ] **Step 3: Run the new oracle comparisons on the current baseline**

Run:

```sh
./test/compare_acl_manifests.sh
./test/compare_capabilities_json.sh
```

Expected: both commands pass while the wrapper baseline is still active.

- [ ] **Step 4: Commit the new test-only seam checks**

```bash
git add test/compare_acl_manifests.sh test/compare_capabilities_json.sh
git commit -m "test: add tauri acl oracle comparisons"
```

### Task 2: Introduce Bazel-Owned ACL Prep Tool

**Files:**
- Create: `tools/tauri_acl_prep/Cargo.toml`
- Create: `tools/tauri_acl_prep/Cargo.lock`
- Create: `tools/tauri_acl_prep/BUILD.bazel`
- Create: `tools/tauri_acl_prep/src/main.rs`
- Modify: `MODULE.bazel`
- Modify: `private/upstream_context_oracle.bzl`

- [ ] **Step 1: Add a dedicated tool crate universe for ACL prep**

```starlark
crate.from_cargo(
    name = "acl_tool_crates",
    cargo_lockfile = "//tools/tauri_acl_prep:Cargo.lock",
    manifests = ["//tools/tauri_acl_prep:Cargo.toml"],
    supported_platform_triples = [
        "aarch64-apple-darwin",
        "x86_64-apple-darwin",
    ],
)
```

- [ ] **Step 2: Add the ACL prep tool crate manifest**

```toml
[package]
name = "tauri-acl-prep"
version = "0.1.0"
edition = "2021"

[dependencies]
anyhow = "1"
serde_json = "1"
tauri-build = "2"
```

- [ ] **Step 3: Add the Bazel target for the ACL prep tool**

```starlark
package(default_visibility = ["//visibility:public"])

load("@acl_tool_crates//:defs.bzl", "aliases", "all_crate_deps")
load("@rules_rust//rust:defs.bzl", "rust_binary")

exports_files([
    "Cargo.toml",
    "Cargo.lock",
])

rust_binary(
    name = "tauri_acl_prep_exec",
    srcs = ["src/main.rs"],
    crate_name = "tauri_acl_prep",
    edition = "2021",
    aliases = aliases(),
    deps = all_crate_deps(normal = True),
)
```

- [ ] **Step 4: Implement the smallest useful tool surface**

```rust
fn main() -> anyhow::Result<()> {
    // parse --config, --frontend-dist, --out-dir
    // set CWD to config parent
    // set OUT_DIR
    // patch TAURI_CONFIG with frontendDist and devUrl = null
    // call the tauri-build ACL preparation entry point only
    // verify acl-manifests.json and capabilities.json exist
    Ok(())
}
```

- [ ] **Step 5: Replace the private macro internals only for a fixture-only path**

```starlark
# Keep the existing public target names.
# Inside the private macro, create:
# - an ACL-prep directory target
# - the existing upstream build script oracle target
# - a comparison/test seam that proves Bazel ACL prep matches oracle ACL prep
```

- [ ] **Step 6: Run the tool build and fixture oracle comparisons**

Run:

```sh
bazel build --action_env=PATH //tools/tauri_acl_prep:tauri_acl_prep_exec
./test/compare_acl_manifests.sh
./test/compare_capabilities_json.sh
```

Expected: tool builds; comparisons still pass while the wrapper oracle remains the source of truth.

- [ ] **Step 7: Commit the ACL-prep tool scaffolding**

```bash
git add MODULE.bazel private/upstream_context_oracle.bzl tools/tauri_acl_prep
git commit -m "feat: add tauri acl prep tool scaffold"
```

### Task 3: Cut the Fixture to Bazel-Owned ACL Prep

**Files:**
- Modify: `test/fixtures/tauri_codegen/src-tauri/BUILD.bazel`
- Modify: `test/validate_rules_rust_codegen_fixture.sh`
- Test: `test/compare_acl_manifests.sh`
- Test: `test/compare_capabilities_json.sh`
- Test: `test/compare_full_codegen_context.sh`
- Test: `test/compare_context_build_config.sh`

- [ ] **Step 1: Route only the fixture ACL side effects through the Bazel tool**

```starlark
# Keep fixture target names stable.
# Use Bazel-owned ACL prep outputs for:
# - acl-manifests.json
# - capabilities.json
# Continue using the wrapper oracle for final tauri-build-context.rs until comparisons stay green.
```

- [ ] **Step 2: Run the fixture validation**

Run:

```sh
./test/validate_rules_rust_codegen_fixture.sh
```

Expected: pass.

- [ ] **Step 3: Run the focused oracle comparisons**

Run:

```sh
./test/compare_acl_manifests.sh
./test/compare_capabilities_json.sh
./test/compare_full_codegen_context.sh
./test/compare_context_build_config.sh
```

Expected: all pass.

- [ ] **Step 4: Commit the fixture ACL-prep cut**

```bash
git add test/fixtures/tauri_codegen/src-tauri/BUILD.bazel test/validate_rules_rust_codegen_fixture.sh
git commit -m "feat: bazelize tauri acl prep for fixture"
```

### Task 4: Reattempt Context Codegen Cutover

**Files:**
- Modify: `private/upstream_context_oracle.bzl`
- Modify: `examples/tauri_with_vite/app/src-tauri/BUILD.bazel`
- Modify: `examples/tauri_with_vite/app/src-tauri/build.rs`
- Modify: `test/fixtures/tauri_codegen/src-tauri/BUILD.bazel`
- Modify: `test/fixtures/tauri_codegen/src-tauri/build.rs`
- Test: `test/validate_examples.sh`
- Test: `test/validate_rules_rust_codegen_fixture.sh`
- Test: `test/compare_full_codegen_context.sh`
- Test: `test/compare_context_build_config.sh`

- [ ] **Step 1: Reintroduce the direct `tauri-codegen` tool behind the private macro**

```starlark
# Replace upstream_build_script only after ACL prep is already Bazel-owned.
# Preserve current target labels consumed by build scripts.
```

- [ ] **Step 2: Switch the fixture first**

Run:

```sh
bazel build --action_env=PATH //test/fixtures/tauri_codegen:codegen_probe
./test/validate_rules_rust_codegen_fixture.sh
./test/compare_full_codegen_context.sh
./test/compare_context_build_config.sh
```

Expected: all pass.

- [ ] **Step 3: Switch the real example second**

Run:

```sh
./test/validate_examples.sh
```

Expected: pass.

- [ ] **Step 4: Commit the full cutover**

```bash
git add private/upstream_context_oracle.bzl examples/tauri_with_vite/app/src-tauri/BUILD.bazel examples/tauri_with_vite/app/src-tauri/build.rs test/fixtures/tauri_codegen/src-tauri/BUILD.bazel test/fixtures/tauri_codegen/src-tauri/build.rs
git commit -m "feat: replace tauri upstream build script oracle"
```

### Task 5: Final Verification and Cleanup

**Files:**
- Modify: `examples/tauri_with_vite/app/src-tauri/BUILD.bazel`
- Modify: `test/fixtures/tauri_codegen/src-tauri/BUILD.bazel`
- Delete: helper files only if no target still references them

- [ ] **Step 1: Remove stale helper sources only after the direct cutover is green**

```text
Delete only if unused:
- examples/tauri_with_vite/app/src-tauri/upstream_build.rs
- test/fixtures/tauri_codegen/src-tauri/upstream_build.rs
```

- [ ] **Step 2: Run the full verification matrix**

Run:

```sh
./test/validate_examples.sh
./test/validate_rules_rust_codegen_fixture.sh
./test/compare_acl_manifests.sh
./test/compare_capabilities_json.sh
./test/compare_full_codegen_context.sh
./test/compare_context_build_config.sh
```

Expected: all pass.

- [ ] **Step 3: Commit cleanup**

```bash
git add -A
git commit -m "chore: remove stale tauri helper sources"
```
