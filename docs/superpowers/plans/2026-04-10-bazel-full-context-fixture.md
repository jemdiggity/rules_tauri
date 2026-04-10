# Bazel Full Context Fixture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove `tauri_build::try_build(...)` from `test/fixtures/tauri_codegen` and have Bazel generate that fixture's `tauri-build-context.rs` directly, while leaving `examples/tauri_with_vite` unchanged.

**Architecture:** Keep upstream Tauri as the runtime dependency and the comparison oracle. For the isolated fixture only, replace the last `build.rs` codegen dependency with a Bazel-generated full context file assembled from already-proven seams: embedded assets, CSP hashes, runtime authority, and normalized build config. The fixture `build.rs` becomes a thin copier from a Bazel-provided file into `OUT_DIR/tauri-build-context.rs`.

**Tech Stack:** Bazel, Starlark `genrule`, `rules_rust`, Python 3, Rust, Tauri runtime crates, shell oracle scripts.

---

### Task 1: Lock the Fixture Oracle Contract

**Files:**
- Modify: `test/compare_full_codegen_context.sh`
- Test: `test/compare_full_codegen_context.sh`

- [ ] **Step 1: Document the normalized seams in the full-context oracle**

Add these comments directly above `normalize_context()` in `test/compare_full_codegen_context.sh`:

```sh
# Normalized seams:
# - embedded assets expression body
# - build.frontend_dist / with_config_parent path roots
# - runtime authority macro body
# - debug cfg wrappers and token formatting
```

- [ ] **Step 2: Verify the baseline oracle is still green**

Run:

```bash
sh ./test/compare_full_codegen_context.sh
```

Expected: `full codegen context comparison passed`

- [ ] **Step 3: Commit the clarified oracle**

```bash
git add test/compare_full_codegen_context.sh
git commit -m "test: clarify full context oracle contract"
```

### Task 2: Add a Bazel Tool That Emits the Full Fixture Context

**Files:**
- Create: `tools/tauri_full_context_fixture.py`
- Modify: `tools/BUILD.bazel`
- Test: `python3 tools/tauri_full_context_fixture.py --help`

- [ ] **Step 1: Add the tool target**

Append this `genrule` to `tools/BUILD.bazel` right after `tauri_embedded_assets_rust_exec`:

```bzl
genrule(
    name = "tauri_full_context_fixture_exec",
    srcs = ["tauri_full_context_fixture.py"],
    outs = ["tauri_full_context_fixture"],
    cmd = "cp $(location tauri_full_context_fixture.py) $@ && chmod 755 $@",
    executable = True,
)
```

Also add the source file to `exports_files([...])`:

```bzl
    "tauri_full_context_fixture.py",
```

- [ ] **Step 2: Create the generator skeleton**

Create `tools/tauri_full_context_fixture.py` with this exact starting content:

```python
#!/usr/bin/env python3
import argparse
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", required=True)
    parser.add_argument("--embedded-assets-rust", required=True)
    parser.add_argument("--runtime-authority-rust", required=True)
    parser.add_argument("--product-name", required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--identifier", required=True)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    embedded_assets = Path(args.embedded_assets_rust).read_text(encoding="utf-8").strip()
    runtime_authority = Path(args.runtime_authority_rust).read_text(encoding="utf-8").strip()
    Path(args.out).write_text(
        (
            "// placeholder full fixture context\n"
            f"const _: &str = {args.product_name!r};\n"
            f"const _: &str = {args.version!r};\n"
            f"const _: &str = {args.identifier!r};\n"
            f"const _: &str = {embedded_assets!r};\n"
            f"const _: &str = {runtime_authority!r};\n"
        ),
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
```

- [ ] **Step 3: Smoke-test the CLI surface**

Run:

```bash
python3 tools/tauri_full_context_fixture.py --help
```

Expected: argparse usage text mentioning `--out`, `--embedded-assets-rust`, and `--runtime-authority-rust`

- [ ] **Step 4: Commit the new tool shell**

```bash
git add tools/BUILD.bazel tools/tauri_full_context_fixture.py
git commit -m "feat: add Bazel full-context fixture generator"
```

### Task 3: Generate the Fixture Full Context in Bazel

**Files:**
- Modify: `test/fixtures/tauri_codegen/src-tauri/BUILD.bazel`
- Test: `bazel build //test/fixtures/tauri_codegen:full_context_rust`

- [ ] **Step 1: Add a dedicated runtime-authority extraction target**

In `test/fixtures/tauri_codegen/src-tauri/BUILD.bazel`, add this `genrule` immediately after `cargo_build_script(...)`:

```bzl
genrule(
    name = "runtime_authority_rust",
    srcs = [":build_script"],
    outs = ["runtime_authority.rs"],
    cmd = """
set -eu
context="$(location :build_script.out_dir)/tauri-build-context.rs"
python3 - "$$context" "$@" <<'PY'
from pathlib import Path
import re
import sys

text = Path(sys.argv[1]).read_text(encoding="utf-8")
match = re.search(r':: tauri :: runtime_authority ! \\(\\{.*?\\}\\)', text, re.S)
if match is None:
    raise SystemExit("failed to find runtime_authority! macro")
Path(sys.argv[2]).write_text(match.group(0) + "\\n", encoding="utf-8")
PY
""",
)
```

- [ ] **Step 2: Add a Bazel-generated full-context target**

Still in `test/fixtures/tauri_codegen/src-tauri/BUILD.bazel`, add this `genrule` after `runtime_authority_rust`:

```bzl
genrule(
    name = "full_context_rust",
    srcs = [
        "//test/fixtures/tauri_codegen:embedded_assets_compressed_rust",
        ":runtime_authority_rust",
    ],
    tools = ["//tools:tauri_full_context_fixture_exec"],
    outs = ["tauri-build-context.rs"],
    cmd = """
set -eu
$(execpath //tools:tauri_full_context_fixture_exec) \
  --out "$@" \
  --embedded-assets-rust "$(location //test/fixtures/tauri_codegen:embedded_assets_compressed_rust)" \
  --runtime-authority-rust "$(location :runtime_authority_rust)" \
  --product-name "tauri-codegen-fixture" \
  --version "0.1.0" \
  --identifier "com.example.tauri-codegen-fixture"
""",
)
```

- [ ] **Step 3: Verify Bazel can build the generated artifact**

Run:

```bash
bazel build //test/fixtures/tauri_codegen/src-tauri:full_context_rust
```

Expected: success, with output at `bazel-bin/test/fixtures/tauri_codegen/src-tauri/tauri-build-context.rs`

- [ ] **Step 4: Commit the fixture Bazel wiring**

```bash
git add test/fixtures/tauri_codegen/src-tauri/BUILD.bazel
git commit -m "feat: generate full fixture context in Bazel"
```

### Task 4: Cut the Fixture Build Script Over to Bazel-Owned Context

**Files:**
- Modify: `test/fixtures/tauri_codegen/src-tauri/BUILD.bazel`
- Modify: `test/fixtures/tauri_codegen/src-tauri/build.rs`
- Test: `./test/validate_rules_rust_codegen_fixture.sh`

- [ ] **Step 1: Expose the generated full context to the build script**

In the existing `cargo_build_script(...)` call in `test/fixtures/tauri_codegen/src-tauri/BUILD.bazel`, add `:full_context_rust` to both `data` and `compile_data`, and replace the old `build_script_env` block with:

```bzl
    build_script_env = {
        "DEP_TAURI_DEV": "false",
        "RULES_TAURI_BAZEL_FULL_CONTEXT": "$(location :full_context_rust)",
    },
```

- [ ] **Step 2: Replace the fixture build script with a pure copy-to-OUT_DIR flow**

Replace the full contents of `test/fixtures/tauri_codegen/src-tauri/build.rs` with:

```rust
use std::path::PathBuf;

fn main() {
    if let Ok(manifest_dir) = std::env::var("CARGO_MANIFEST_DIR") {
        std::env::set_current_dir(&manifest_dir)
            .unwrap_or_else(|error| panic!("failed to chdir to {manifest_dir}: {error}"));
    }

    let full_context_path =
        std::env::var("RULES_TAURI_BAZEL_FULL_CONTEXT").expect("missing RULES_TAURI_BAZEL_FULL_CONTEXT");
    println!("cargo:rerun-if-env-changed=RULES_TAURI_BAZEL_FULL_CONTEXT");
    println!("cargo:rerun-if-changed={full_context_path}");

    let out_path = PathBuf::from(std::env::var("OUT_DIR").expect("missing OUT_DIR"))
        .join("tauri-build-context.rs");
    std::fs::copy(&full_context_path, &out_path).unwrap_or_else(|error| {
        panic!(
            "failed to copy {} to {}: {error}",
            full_context_path,
            out_path.display()
        )
    });
}
```

- [ ] **Step 3: Run the fixture validation and capture the first real mismatch**

Run:

```bash
./test/validate_rules_rust_codegen_fixture.sh
```

Expected initially: failure, because the placeholder generator output is not yet a real Tauri context

- [ ] **Step 4: Commit the cutover**

```bash
git add test/fixtures/tauri_codegen/src-tauri/BUILD.bazel test/fixtures/tauri_codegen/src-tauri/build.rs
git commit -m "feat: route fixture build script through Bazel context"
```

### Task 5: Make the Generated Context Match the Fixture Oracle

**Files:**
- Modify: `tools/tauri_full_context_fixture.py`
- Test: `sh ./test/compare_full_codegen_context.sh`
- Test: `sh ./test/compare_acl_resolution.sh`
- Test: `sh ./test/compare_runtime_authority_resolution.sh`

- [ ] **Step 1: Replace the placeholder generator output with a real fixture context**

Update `tools/tauri_full_context_fixture.py` so it writes one Rust expression matching the fixture shape that `tauri_build_context!()` expects. Use this exact expression template in the generated output:

```rust
{
    #[allow(unused_imports)]
    use ::tauri::utils::assets::{CspHash, EmbeddedAssets, phf, phf::phf_map};
    let assets = inner({EMBEDDED_ASSETS});
    ::tauri::Context::new(
        ::tauri::generate_package_info!(
            name: "tauri-codegen-fixture",
            version: "0.1.0",
            authors: "you",
            description: ""
        ),
        assets,
        ::tauri::utils::config::Config::parse(
            include_str!("tauri.conf.json")
        )
        .expect("failed to parse tauri.conf.json")
        .with_config_parent("../dist"),
        ::tauri::runtime_authority!({AUTH}),
        ::std::vec::Vec::new(),
    )
}
```

In Python, substitute:
- `{EMBEDDED_ASSETS}` with the contents of `--embedded-assets-rust`
- `{AUTH}` with the contents of `--runtime-authority-rust` after stripping the outer `:: tauri :: runtime_authority ! (` and trailing `)`

- [ ] **Step 2: Make the generator normalize the fixture build config**

Inside `tools/tauri_full_context_fixture.py`, hardcode the fixture build config to:

```rust
build: ::tauri::utils::config::BuildConfig {
    runner: None,
    dev_url: None,
    frontend_dist: ::core::option::Option::Some(
        ::tauri::utils::config::FrontendDist::Directory(::std::path::PathBuf::from("../dist"))
    ),
    before_dev_command: None,
    before_build_command: None,
    before_bundle_command: None,
    features: None,
    remove_unused_commands: false,
    additional_watch_folders: Vec::new(),
}
```

Use the same `../dist` normalization the current oracle expects.

- [ ] **Step 3: Run the focused oracles until they all pass**

Run:

```bash
sh ./test/compare_full_codegen_context.sh
sh ./test/compare_acl_resolution.sh
sh ./test/compare_runtime_authority_resolution.sh
./test/validate_rules_rust_codegen_fixture.sh
```

Expected:
- `full codegen context comparison passed`
- `acl resolution comparison passed`
- `runtime authority ACL resolution comparison passed`
- `rules_rust tauri codegen fixture passed`

- [ ] **Step 4: Commit the working generator**

```bash
git add tools/tauri_full_context_fixture.py
git commit -m "feat: replace fixture tauri build context with Bazel output"
```

### Task 6: Prove the Real App Is Still Unchanged

**Files:**
- Test: `test/validate_examples.sh`
- Test: `test/compare_tauri_parity.sh`

- [ ] **Step 1: Verify the real app still builds and packages**

Run:

```bash
./test/validate_examples.sh
```

Expected: `rules_tauri example validation passed`

- [ ] **Step 2: Verify the upstream parity oracle still passes**

Run:

```bash
./test/compare_tauri_parity.sh
```

Expected: `tauri parity comparison passed`

- [ ] **Step 3: Commit only if Task 6 required follow-up edits**

```bash
git add -A
git commit -m "test: verify fixture cutover leaves app parity intact"
```

Skip this step if no files changed during Task 6.

### Task 7: Document the New Boundary

**Files:**
- Modify: `docs/testing.md`
- Modify: `examples/tauri_with_vite/README.md`
- Test: `git diff --check`

- [ ] **Step 1: Update the docs**

Add these points:
- `test/fixtures/tauri_codegen` no longer calls `tauri_build::try_build(...)`
- the fixture is now the Bazel-owned full-context proving ground
- `examples/tauri_with_vite` still uses upstream `build.rs` generation for now

- [ ] **Step 2: Check diff hygiene**

Run:

```bash
git diff --check
```

Expected: no output

- [ ] **Step 3: Commit the docs**

```bash
git add docs/testing.md examples/tauri_with_vite/README.md
git commit -m "docs: describe Bazel-owned fixture context boundary"
```

### Task 8: Final Verification Sweep

**Files:**
- Test: `test/validate_rules_rust_codegen_fixture.sh`
- Test: `test/compare_full_codegen_context.sh`
- Test: `test/compare_acl_resolution.sh`
- Test: `test/compare_runtime_authority_resolution.sh`
- Test: `test/validate_examples.sh`
- Test: `test/compare_tauri_parity.sh`

- [ ] **Step 1: Run the full verification suite**

Run:

```bash
./test/validate_rules_rust_codegen_fixture.sh
sh ./test/compare_full_codegen_context.sh
sh ./test/compare_acl_resolution.sh
sh ./test/compare_runtime_authority_resolution.sh
./test/validate_examples.sh
./test/compare_tauri_parity.sh
```

Expected:
- `rules_rust tauri codegen fixture passed`
- `full codegen context comparison passed`
- `acl resolution comparison passed`
- `runtime authority ACL resolution comparison passed`
- `rules_tauri example validation passed`
- `tauri parity comparison passed`

- [ ] **Step 2: Confirm the worktree is clean**

Run:

```bash
git status --short
```

Expected: no output

- [ ] **Step 3: Final commit if verification forced any extra edits**

```bash
git add -A
git commit -m "test: lock in Bazel full-context fixture parity"
```

Skip this step if the worktree is already clean.
