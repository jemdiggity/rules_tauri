# Real Example `build.rs` Cutover Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove `tauri_build::try_build(...)` from the active `examples/tauri_with_vite` build path while keeping the example runnable and preserving upstream parity oracles.

**Architecture:** Mirror the proven fixture pattern in the real example. A dedicated `upstream_build.rs` target still runs upstream Tauri compile-time generation, Bazel patches only the embedded-assets seam in the helper-generated context, and the actual example `build.rs` becomes a thin copier/emitter that stages the Bazel-owned context plus helper outputs into its own `OUT_DIR` and reproduces the helper’s build-script contract.

**Tech Stack:** Bazel, rules_rust, Rust build scripts, upstream Tauri (`tauri-build`, `tauri-codegen`), Python seam patcher, pnpm/Vite example frontend

---

## File Responsibilities

- Modify: `examples/tauri_with_vite/app/src-tauri/BUILD.bazel`
  Wire the real example to use a helper upstream build script, a Bazel-generated full context artifact, and a build-script contract test.

- Modify: `examples/tauri_with_vite/app/src-tauri/build.rs`
  Remove `tauri_build::try_build(...)` from the active path. Copy the Bazel-generated context and helper out-dir into the real `OUT_DIR`, then emit the helper-equivalent `cargo:` contract.

- Create: `examples/tauri_with_vite/app/src-tauri/upstream_build.rs`
  Run upstream `tauri_build::try_build(...)` for the example helper target and normalize generated `BuildConfig.frontend_dist` back to `../dist`.

- Create: `examples/tauri_with_vite/app/src-tauri/build_contract.rs`
  Hold shared build-script contract helpers for the real example so contract logic is testable and reused by both build scripts.

- Modify: `tools/tauri_full_context_fixture.py`
  Reuse the existing patcher for the real example helper-generated context if any example-specific assumptions need to be generalized.

- Modify: `test/validate_examples.sh`
  Add a real-example build-script contract assertion that compares the active example build script sidecars with the helper sidecars.

- Modify or create: `test/compare_tauri_parity.sh`
  Keep the parity test aligned with the new build path if any file locations or sidecar assertions move.

- Create: `examples/tauri_with_vite/app/src-tauri/build_contract.rs` test target in BUILD
  Give the contract helpers a real Rust unit test target, including divergent identifier coverage where appropriate.

---

### Task 1: Add Example Helper Build Script Inputs

**Files:**
- Create: `examples/tauri_with_vite/app/src-tauri/build_contract.rs`
- Create: `examples/tauri_with_vite/app/src-tauri/upstream_build.rs`
- Modify: `examples/tauri_with_vite/app/src-tauri/BUILD.bazel`
- Test: `examples/tauri_with_vite/app/src-tauri:build_contract_test`

- [ ] **Step 1: Write the failing contract helper test**

Add a shared helper module with tests modeled on the fixture helper:

```rust
pub fn is_dev_enabled(dep_tauri_dev: Option<&str>) -> bool {
    dep_tauri_dev == Some("true")
}

pub fn android_package_names(identifier: &str) -> (String, String) {
    let segments: Vec<_> = identifier.split('.').collect();
    let (app_name_segment, prefix_segments) = segments
        .split_last()
        .expect("identifier must contain at least one segment");

    let app_name = app_name_segment.replace('-', "_");
    let prefix = prefix_segments
        .iter()
        .map(|segment| segment.replace(['_', '-'], "_1"))
        .collect::<Vec<_>>()
        .join("_");

    (app_name, prefix)
}

#[cfg(test)]
mod tests {
    use super::{android_package_names, is_dev_enabled};

    #[test]
    fn dev_cfg_only_when_dep_tauri_dev_is_true() {
        assert!(is_dev_enabled(Some("true")));
        assert!(!is_dev_enabled(Some("false")));
        assert!(!is_dev_enabled(None));
    }

    #[test]
    fn android_package_names_ignore_product_name_and_escape_identifier_segments() {
        let (app_name, prefix) = android_package_names("com.foo_bar-baz.actual-app");
        assert_eq!(app_name, "actual_app");
        assert_eq!(prefix, "com_foo_1bar_1baz");
    }
}
```

- [ ] **Step 2: Wire the test target and verify it fails**

Modify `examples/tauri_with_vite/app/src-tauri/BUILD.bazel` to include:

```python
load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")
```

and:

```python
rust_test(
    name = "build_contract_test",
    srcs = ["build_contract.rs"],
    crate_name = "tauri_with_vite_build_contract_test",
    edition = "2021",
)
```

Run: `bazel test //examples/tauri_with_vite/app/src-tauri:build_contract_test`

Expected: `FAIL` because `build_contract.rs` does not exist yet.

- [ ] **Step 3: Add the helper module and helper build script source**

Create `examples/tauri_with_vite/app/src-tauri/build_contract.rs` with the helper code from Step 1.

Create `examples/tauri_with_vite/app/src-tauri/upstream_build.rs` as the example-local upstream oracle:

```rust
mod build_contract;

use quote::quote;
use std::path::PathBuf;
use syn::visit_mut::{self, VisitMut};

fn main() {
    if let Ok(manifest_dir) = std::env::var("CARGO_MANIFEST_DIR") {
        std::env::set_current_dir(&manifest_dir)
            .unwrap_or_else(|error| panic!("failed to chdir to {manifest_dir}: {error}"));
    }

    if let Ok(frontend_dist) = std::env::var("RULES_TAURI_FRONTEND_DIST") {
        let config_patch = serde_json::json!({
            "build": {
                "devUrl": serde_json::Value::Null,
                "frontendDist": frontend_dist,
            },
        });
        std::env::set_var("TAURI_CONFIG", config_patch.to_string());
    }
    println!("cargo:rerun-if-env-changed=RULES_TAURI_FRONTEND_DIST");

    let attributes = tauri_build::Attributes::new().codegen(tauri_build::CodegenContext::new());
    tauri_build::try_build(attributes).expect("failed to generate Tauri build context");
    normalize_build_config_paths();
}

fn normalize_build_config_paths() {
    let context_path = PathBuf::from(std::env::var("OUT_DIR").expect("missing OUT_DIR"))
        .join("tauri-build-context.rs");
    let context_source = std::fs::read_to_string(&context_path)
        .unwrap_or_else(|error| panic!("failed to read {}: {error}", context_path.display()));
    let mut context_expr: syn::Expr = syn::parse_str(&context_source).unwrap_or_else(|error| {
        panic!(
            "failed to parse generated Tauri context {}: {error}",
            context_path.display()
        )
    });
    let mut patcher = GeneratedContextPathPatcher {
        frontend_dist: syn::LitStr::new("../dist", proc_macro2::Span::call_site()),
    };
    patcher.visit_expr_mut(&mut context_expr);

    std::fs::write(&context_path, format!("{}\n", quote!(#context_expr)))
        .unwrap_or_else(|error| panic!("failed to write {}: {error}", context_path.display()));
}

struct GeneratedContextPathPatcher {
    frontend_dist: syn::LitStr,
}

impl VisitMut for GeneratedContextPathPatcher {
    fn visit_expr_struct_mut(&mut self, node: &mut syn::ExprStruct) {
        visit_mut::visit_expr_struct_mut(self, node);

        let Some(last_segment) = node.path.segments.last() else {
            return;
        };
        if last_segment.ident != "BuildConfig" {
            return;
        }

        for field in &mut node.fields {
            let syn::Member::Named(member) = &field.member else {
                continue;
            };
            if member == "frontend_dist" {
                let frontend_dist = &self.frontend_dist;
                field.expr = syn::parse_quote!(
                    :: core :: option :: Option :: Some(
                        :: tauri :: utils :: config :: FrontendDist :: Directory(
                            :: std :: path :: PathBuf :: from(#frontend_dist)
                        )
                    )
                );
            }
        }
    }
}
```

- [ ] **Step 4: Add the helper files to the example build graph**

Modify `examples/tauri_with_vite/app/src-tauri/BUILD.bazel`:

```python
filegroup(
    name = "cargo_srcs",
    srcs = [
        "Cargo.lock",
        "Cargo.toml",
        "tauri.conf.json",
        "build.rs",
        "build_contract.rs",
        "upstream_build.rs",
    ] + glob([
        "capabilities/**",
        "icons/**",
        "src/**/*.rs",
    ]),
)
```

Update the real `build_script` target sources:

```python
srcs = [
    "build.rs",
    "build_contract.rs",
],
```

Add the new helper target:

```python
cargo_build_script(
    name = "upstream_build_script",
    srcs = [
        "upstream_build.rs",
        "build_contract.rs",
    ],
    crate_root = "upstream_build.rs",
    crate_name = "upstream_build_script_build",
    edition = "2021",
    pkg_name = "tauri-with-vite",
    version = "0.1.0",
    rundir = "examples/tauri_with_vite/app/src-tauri",
    aliases = aliases(build = True),
    deps = all_crate_deps(build = True),
    link_deps = [
        "@example_crates//:tauri",
        "@example_crates//:tauri-plugin-opener",
    ],
    proc_macro_deps = all_crate_deps(build_proc_macro = True),
    data = [
        ":cargo_srcs",
        ":tauri_build_data",
        "//examples/tauri_with_vite:frontend_dist",
    ],
    compile_data = [
        ":cargo_srcs",
        ":tauri_build_data",
        "//examples/tauri_with_vite:frontend_dist",
    ],
    build_script_env = {
        "DEP_TAURI_DEV": "false",
        "RULES_TAURI_FRONTEND_DIST": "$(location //examples/tauri_with_vite:frontend_dist)",
    },
)
```

- [ ] **Step 5: Run the helper unit test and helper build target**

Run:
- `bazel test //examples/tauri_with_vite/app/src-tauri:build_contract_test`
- `bazel build //examples/tauri_with_vite/app/src-tauri:upstream_build_script`

Expected:
- test `PASS`
- helper build target `PASS`

- [ ] **Step 6: Commit**

```bash
git add examples/tauri_with_vite/app/src-tauri/BUILD.bazel \
  examples/tauri_with_vite/app/src-tauri/build_contract.rs \
  examples/tauri_with_vite/app/src-tauri/upstream_build.rs
git commit -m "feat: add upstream helper build script for real example"
```

### Task 2: Generate Full Context for the Real Example

**Files:**
- Modify: `examples/tauri_with_vite/app/src-tauri/BUILD.bazel`
- Modify: `tools/tauri_full_context_fixture.py`
- Test: `test/compare_tauri_parity.sh`

- [ ] **Step 1: Add the failing full-context genrule wiring**

Add a `full_context_rust` genrule to `examples/tauri_with_vite/app/src-tauri/BUILD.bazel`:

```python
genrule(
    name = "full_context_rust",
    srcs = [
        "//examples/tauri_with_vite:embedded_assets_rust",
        ":upstream_build_script",
    ],
    tools = ["//tools:tauri_full_context_fixture_exec"],
    outs = ["tauri-build-context.rs"],
    cmd = """
set -eu
$(execpath //tools:tauri_full_context_fixture_exec) \
  --out "$@" \
  --embedded-assets-rust "$(location //examples/tauri_with_vite:embedded_assets_rust)" \
  --upstream-context-rust "$(location :upstream_build_script)/tauri-build-context.rs"
""",
)
```

Run: `bazel build //examples/tauri_with_vite/app/src-tauri:full_context_rust`

Expected: `FAIL` if the current helper outputs or patcher assumptions are still fixture-specific.

- [ ] **Step 2: Generalize the context patcher only if needed**

If the genrule fails because `tools/tauri_full_context_fixture.py` makes fixture-specific assumptions, generalize only the necessary parts. Keep the interface:

```python
parser.add_argument("--out", required=True)
parser.add_argument("--embedded-assets-rust", required=True)
parser.add_argument("--upstream-context-rust", required=True)
```

Do not broaden the seam. The tool should still:
- read helper `tauri-build-context.rs`
- render Bazel-owned embedded assets
- replace only the final `inner(...)` assets expression

- [ ] **Step 3: Make the real build script depend on the generated full context**

Update the real `build_script` target in `examples/tauri_with_vite/app/src-tauri/BUILD.bazel`:

```python
data = [
    ":cargo_srcs",
    ":tauri_build_data",
    ":full_context_rust",
    ":upstream_build_script",
    "//examples/tauri_with_vite:frontend_dist",
    "//examples/tauri_with_vite:embedded_assets_rust",
],
compile_data = [
    ":cargo_srcs",
    ":tauri_build_data",
    ":full_context_rust",
    ":upstream_build_script",
    "//examples/tauri_with_vite:frontend_dist",
    "//examples/tauri_with_vite:embedded_assets_rust",
],
build_script_env = {
    "DEP_TAURI_DEV": "false",
    "RULES_TAURI_BAZEL_FULL_CONTEXT": "$(location :full_context_rust)",
    "RULES_TAURI_BAZEL_UPSTREAM_OUT_DIR": "$(location :upstream_build_script)",
},
```

Run: `bazel build //examples/tauri_with_vite/app/src-tauri:build_script`

Expected: `PASS`

- [ ] **Step 4: Commit**

```bash
git add examples/tauri_with_vite/app/src-tauri/BUILD.bazel \
  tools/tauri_full_context_fixture.py
git commit -m "feat: generate real example context from helper output"
```

### Task 3: Cut Over the Real Example `build.rs`

**Files:**
- Modify: `examples/tauri_with_vite/app/src-tauri/build.rs`
- Test: `//examples/tauri_with_vite/app/src-tauri:tauri_with_vite_bin`

- [ ] **Step 1: Replace the active build script with the copier/emitter path**

Overwrite the current `examples/tauri_with_vite/app/src-tauri/build.rs` structure to mirror the fixture pattern:

```rust
mod build_contract;

use std::fs;
use std::path::{Path, PathBuf};

fn copy_tree(source: &Path, destination: &Path) { /* mirror fixture implementation */ }

fn copy_upstream_out_dir(upstream_out_dir: &Path, out_dir: &Path) { /* mirror fixture implementation */ }

fn emit_upstream_contract(out_dir: &Path) {
    let config: serde_json::Value =
        serde_json::from_str(&fs::read_to_string("tauri.conf.json").expect("failed to read tauri.conf.json"))
            .expect("failed to parse tauri.conf.json");
    let identifier = config["identifier"]
        .as_str()
        .expect("tauri.conf.json must contain identifier");
    let (android_package_name_app_name, android_package_name_prefix) =
        build_contract::android_package_names(identifier);
    let target_os = std::env::var("CARGO_CFG_TARGET_OS").expect("missing CARGO_CFG_TARGET_OS");
    let mobile = target_os == "ios" || target_os == "android";

    println!("cargo:rustc-check-cfg=cfg(desktop)");
    println!("cargo:rustc-check-cfg=cfg(mobile)");
    if mobile {
        println!("cargo:rustc-cfg=mobile");
    } else {
        println!("cargo:rustc-cfg=desktop");
    }
    println!("cargo:rustc-check-cfg=cfg(dev)");
    if build_contract::is_dev_enabled(std::env::var("DEP_TAURI_DEV").ok().as_deref()) {
        println!("cargo:rustc-cfg=dev");
    }
    println!(
        "cargo:rustc-env=TAURI_ANDROID_PACKAGE_NAME_APP_NAME={}",
        android_package_name_app_name
    );
    println!(
        "cargo:rustc-env=TAURI_ANDROID_PACKAGE_NAME_PREFIX={}",
        android_package_name_prefix
    );
    if let Ok(target) = std::env::var("TARGET") {
        println!("cargo:rustc-env=TAURI_ENV_TARGET_TRIPLE={target}");
    }
    println!(
        "cargo:PERMISSION_FILES_PATH={}",
        out_dir
            .join("app-manifest")
            .join("__app__-permission-files")
            .display()
    );
}

fn main() {
    if let Ok(manifest_dir) = std::env::var("CARGO_MANIFEST_DIR") {
        std::env::set_current_dir(&manifest_dir)
            .unwrap_or_else(|error| panic!("failed to chdir to {manifest_dir}: {error}"));
    }

    println!("cargo:rerun-if-env-changed=TAURI_CONFIG");
    println!("cargo:rerun-if-env-changed=REMOVE_UNUSED_COMMANDS");
    println!("cargo:rerun-if-changed=tauri.conf.json");
    println!("cargo:rerun-if-changed=capabilities");
    println!("cargo:rerun-if-changed=../dist");

    let full_context_path =
        std::env::var("RULES_TAURI_BAZEL_FULL_CONTEXT").expect("missing RULES_TAURI_BAZEL_FULL_CONTEXT");
    println!("cargo:rerun-if-env-changed=RULES_TAURI_BAZEL_FULL_CONTEXT");
    println!("cargo:rerun-if-changed={full_context_path}");
    let upstream_out_dir = PathBuf::from(
        std::env::var("RULES_TAURI_BAZEL_UPSTREAM_OUT_DIR")
            .expect("missing RULES_TAURI_BAZEL_UPSTREAM_OUT_DIR"),
    );
    println!("cargo:rerun-if-env-changed=RULES_TAURI_BAZEL_UPSTREAM_OUT_DIR");
    println!("cargo:rerun-if-changed={}", upstream_out_dir.display());

    let out_dir = PathBuf::from(std::env::var("OUT_DIR").expect("missing OUT_DIR"));
    let out_path = out_dir.join("tauri-build-context.rs");
    std::fs::copy(&full_context_path, &out_path).unwrap_or_else(|error| {
        panic!(
            "failed to copy {} to {}: {error}",
            full_context_path,
            out_path.display()
        )
    });

    copy_upstream_out_dir(&upstream_out_dir, &out_dir);
    emit_upstream_contract(&out_dir);
}
```

- [ ] **Step 2: Verify the real example still compiles**

Run:
- `bazel build //examples/tauri_with_vite/app/src-tauri:tauri_with_vite_bin`
- `bazel build //examples/tauri_with_vite:app_arm64`

Expected:
- both `PASS`

- [ ] **Step 3: Launch the app**

Run:

```bash
bazel build //examples/tauri_with_vite:app_arm64
open -n bazel-bin/examples/tauri_with_vite/app_arm64.app
```

Expected:
- app launches
- the Vue UI renders correctly, not a blank window

- [ ] **Step 4: Commit**

```bash
git add examples/tauri_with_vite/app/src-tauri/build.rs
git commit -m "feat: remove tauri build from real example path"
```

### Task 4: Add Real-Example Build-Script Contract Guardrail

**Files:**
- Modify: `test/validate_examples.sh`
- Test: `test/validate_examples.sh`

- [ ] **Step 1: Add failing sidecar comparison logic for the real example**

Extend `test/validate_examples.sh` to compare the real example build-script sidecars against the helper sidecars:

```sh
example_build_flags="$repo_root/bazel-bin/examples/tauri_with_vite/app/src-tauri/build_script.flags"
example_build_env="$repo_root/bazel-bin/examples/tauri_with_vite/app/src-tauri/build_script.env"
example_build_depenv="$repo_root/bazel-bin/examples/tauri_with_vite/app/src-tauri/build_script.depenv"
example_upstream_flags="$repo_root/bazel-bin/examples/tauri_with_vite/app/src-tauri/upstream_build_script.flags"
example_upstream_env="$repo_root/bazel-bin/examples/tauri_with_vite/app/src-tauri/upstream_build_script.env"
example_upstream_depenv="$repo_root/bazel-bin/examples/tauri_with_vite/app/src-tauri/upstream_build_script.depenv"

cmp -s "$example_build_flags" "$example_upstream_flags"
cmp -s "$example_build_env" "$example_upstream_env"
python3 - "$example_build_depenv" "$example_upstream_depenv" <<'PY'
import pathlib
import re
import sys

def normalize(text: str) -> str:
    return re.sub(r"build_script\\.out_dir", "OUT_DIR", re.sub(r"upstream_build_script\\.out_dir", "OUT_DIR", text))

build = normalize(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
upstream = normalize(pathlib.Path(sys.argv[2]).read_text(encoding="utf-8"))
if build != upstream:
    raise SystemExit(f"example build script depenv mismatch\\nexpected:\\n{upstream}\\nactual:\\n{build}")
PY
```

Run: `./test/validate_examples.sh`

Expected: `FAIL` until the real-example cutover is complete and the contract matches.

- [ ] **Step 2: Make the test pass**

After Task 3 is complete, rerun:

```bash
./test/validate_examples.sh
```

Expected:
- `PASS`
- the new sidecar checks pass for the real example

- [ ] **Step 3: Commit**

```bash
git add test/validate_examples.sh
git commit -m "test: verify real example build script contract"
```

### Task 5: Run Full Verification and Prepare Handoff

**Files:**
- Modify: none unless failures require targeted fixes
- Test: all relevant validation scripts

- [ ] **Step 1: Run the full real-example verification suite**

Run:

```bash
./test/validate_rules_rust_codegen_fixture.sh
sh ./test/compare_context_build_config.sh
sh ./test/compare_acl_resolution.sh
sh ./test/compare_runtime_authority_resolution.sh
sh ./test/compare_full_codegen_context.sh
./test/validate_examples.sh
./test/compare_tauri_parity.sh
git diff --check
```

Expected:
- all commands `PASS`
- `git diff --check` prints nothing

- [ ] **Step 2: Summarize residual risk**

Record the remaining deliberate dependency:

```text
The real example active build path no longer calls tauri_build::try_build(...), but the helper upstream_build.rs target still does and remains the oracle for context/sidecar parity.
```

- [ ] **Step 3: Commit any final verification-only fixes if needed**

If a tiny cleanup is required:

```bash
git add <exact files>
git commit -m "fix: clean up real example build rs cutover"
```

If no cleanup is needed, skip this step.
