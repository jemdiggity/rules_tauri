# Full Semantic Bazelfication Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove upstream `tauri-build` and `tauri-codegen` from the active Bazel release path by replacing the remaining context-generation semantics with repo-owned Bazel exec tools, using a dedicated fixture oracle for each semantic seam before replacement.

**Architecture:** Keep the current private Bazel pipeline shape and replace the remaining upstream-backed semantics inside `tools/tauri_context_codegen` one seam at a time. For each seam, first add a narrow fixture oracle that captures upstream behavior, then replace only that seam with repo-owned logic, while keeping the broader fixture/example/parity suite green.

**Tech Stack:** Bazel/Starlark, rules_rust, Rust exec tools, Python/shell oracle scripts, Tauri fixture/example apps

---

## File Responsibilities

- Modify: `tools/tauri_context_codegen/src/main.rs`
  Replace upstream `tauri_codegen::get_config(...)` and `tauri_codegen::context_codegen(...)` incrementally with repo-owned logic.

- Modify: `tools/tauri_context_codegen/Cargo.toml`
  Remove upstream compile-time crate dependencies only after replacement code is in place.

- Modify: `tools/tauri_context_codegen/BUILD.bazel`
  Keep tool/test wiring aligned with the rewritten context generator.

- Modify: `private/upstream_context_oracle.bzl`
  Keep orchestration stable while threading any new explicit inputs the repo-owned generator needs.

- Modify: `test/fixtures/tauri_codegen/src-tauri/BUILD.bazel`
  Add any fixture-side oracle targets or helper data needed for seam-level comparisons.

- Create: `test/compare_context_config_normalization.sh`
  Narrow fixture oracle for config-loading and normalization semantics.

- Create: `test/compare_context_runtime_shape.sh`
  Narrow fixture oracle for the context assembly semantics that matter to runtime behavior.

- Modify: `test/compare_full_codegen_context.sh`
  Keep it as the broader fixture guardrail after seam replacements, only if normalization needs to expand.

- Modify: `test/compare_context_build_config.sh`
  Keep the build-config seam guardrail aligned with the repo-owned generator.

- Modify or create fixture helper inputs under `test/fixtures/tauri_codegen/`
  Add any extra fixture inputs needed to exercise seam-level upstream behavior explicitly.

- Verification: 
  - `./test/validate_rules_rust_codegen_fixture.sh`
  - `./test/compare_context_config_normalization.sh`
  - `./test/compare_context_runtime_shape.sh`
  - `./test/compare_context_build_config.sh`
  - `./test/compare_full_codegen_context.sh`
  - `bash ./test/compare_acl_resolution.sh`
  - `bash ./test/compare_runtime_authority_resolution.sh`
  - `./test/validate_examples.sh`
  - `./test/compare_tauri_parity.sh`

### Task 1: Add a Narrow Oracle for Config Loading and Normalization

**Files:**
- Create: `test/compare_context_config_normalization.sh`
- Modify: `test/fixtures/tauri_codegen/src-tauri/BUILD.bazel`
- Modify if needed: `test/fixtures/tauri_codegen/src-tauri/tauri.conf.json`
- Test: `./test/compare_context_config_normalization.sh`

- [ ] **Step 1: Write the failing fixture oracle script**

Create `test/compare_context_config_normalization.sh` as a focused comparison that:

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

oracle_context=$(find "$tmpdir/target/debug/build" -path '*/out/tauri-build-context.rs' -print | head -n1)
test -n "$oracle_context"

bazel build --action_env=PATH //test/fixtures/tauri_codegen:codegen_probe >/dev/null
bazel_context="$repo_root/bazel-bin/test/fixtures/tauri_codegen/src-tauri/build_script.out_dir/tauri-build-context.rs"

python3 - "$oracle_context" "$bazel_context" <<'PY'
import pathlib
import re
import sys

def normalize(text: str) -> tuple[str, str]:
    build_match = re.search(
        r'build : :: tauri :: utils :: config :: BuildConfig \{.*?additional_watch_folders : Vec :: new \(\) \}',
        text,
        re.S,
    )
    if not build_match:
        raise SystemExit("failed to locate BuildConfig block")

    parent_match = re.search(r'\. ?with_config_parent \((.*?)\)', text, re.S)
    if not parent_match:
        raise SystemExit("failed to locate with_config_parent call")

    build = re.sub(r"\s+", " ", build_match.group(0)).strip()
    parent = re.sub(r'"[^"]*/src-tauri"', '"$MANIFEST_DIR"', parent_match.group(1))
    parent = re.sub(r"\s+", " ", parent).strip()
    return build, parent

oracle = normalize(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
bazel = normalize(pathlib.Path(sys.argv[2]).read_text(encoding="utf-8"))

if oracle != bazel:
    raise SystemExit(
        "context config normalization comparison failed\n"
        f"expected: {oracle!r}\n"
        f"actual:   {bazel!r}"
    )
PY

echo "context config normalization comparison passed"
```

- [ ] **Step 2: Run the new oracle to verify it passes on the current upstream-backed baseline**

Run: `./test/compare_context_config_normalization.sh`
Expected: `PASS`

- [ ] **Step 3: Commit the new seam oracle**

```bash
git add test/compare_context_config_normalization.sh
git commit -m "test: add context config normalization oracle"
```

### Task 2: Replace Config Loading and Normalization in the Bazel Context Tool

**Files:**
- Modify: `tools/tauri_context_codegen/src/main.rs`
- Modify if needed: `tools/tauri_context_codegen/Cargo.toml`
- Test:
  - `./test/compare_context_config_normalization.sh`
  - `./test/compare_context_build_config.sh`
  - `./test/compare_full_codegen_context.sh`

- [ ] **Step 1: Write a focused unit-style failing change in the context tool**

Replace the direct upstream config-loading call:

```rust
let (mut config_value, config_parent) =
    tauri_codegen::get_config(&config).with_context(|| format!("failed to read {}", config.display()))?;
config_value.build.dev_url = None;
```

with repo-owned helpers shaped like:

```rust
let config_parent = config
    .parent()
    .context("`--config` must include a parent directory")?
    .to_path_buf();
let mut config_value = load_config(&config, TARGET_TRIPLE)?;
config_value.build.dev_url = None;
```

and add helper skeletons that intentionally leave behavior incomplete at first:

```rust
fn load_config(config_path: &Path, _target_triple: &str) -> Result<tauri_utils::config::Config> {
    let config_json = fs::read_to_string(config_path)
        .with_context(|| format!("failed to read {}", config_path.display()))?;
    serde_json::from_str(&config_json)
        .with_context(|| format!("failed to parse {}", config_path.display()))
}
```

- [ ] **Step 2: Run the seam oracle to verify it fails for the right reason**

Run: `./test/compare_context_config_normalization.sh`
Expected: `FAIL` because the repo-owned loader does not yet reproduce upstream config parsing/normalization semantics.

- [ ] **Step 3: Implement the minimal repo-owned config loading needed to restore the seam**

Update `tools/tauri_context_codegen/src/main.rs` to:

- parse `tauri.conf.json` through `tauri_utils::config::parse::read_from(...)`
- pass an explicit target derived from `TARGET_TRIPLE`
- use the config file’s parent directory rather than ambient cwd
- avoid any direct call to `tauri_codegen::get_config(...)`

The resulting helper should look like:

```rust
fn load_config(config_path: &Path, target_triple: &str) -> Result<tauri_utils::config::Config> {
    let config_parent = config_path
        .parent()
        .context("config path must have parent")?;
    let target = tauri_utils::platform::Target::from_triple(target_triple);
    let (config_value, _paths) = tauri_utils::config::parse::read_from(target, config_parent)
        .with_context(|| format!("failed to parse config under {}", config_parent.display()))?;
    serde_json::from_value(config_value).context("failed to decode normalized Tauri config")
}
```

- [ ] **Step 4: Re-run the config seam oracle**

Run: `./test/compare_context_config_normalization.sh`
Expected: `PASS`

- [ ] **Step 5: Re-run the broader fixture guardrails**

Run:

```bash
./test/compare_context_build_config.sh
./test/compare_full_codegen_context.sh
```

Expected: both `PASS`

- [ ] **Step 6: Commit the config-loading replacement**

```bash
git add tools/tauri_context_codegen/src/main.rs tools/tauri_context_codegen/Cargo.toml
git commit -m "feat: own context config normalization"
```

### Task 3: Add a Narrow Oracle for Runtime-Relevant Context Assembly

**Files:**
- Create: `test/compare_context_runtime_shape.sh`
- Modify if needed: `test/fixtures/tauri_codegen/src-tauri/BUILD.bazel`
- Test: `./test/compare_context_runtime_shape.sh`

- [ ] **Step 1: Write the failing runtime-shape oracle**

Create `test/compare_context_runtime_shape.sh` as a focused comparison that extracts and compares only the runtime-relevant seams from the upstream and Bazel-generated contexts:

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

oracle_context=$(find "$tmpdir/target/debug/build" -path '*/out/tauri-build-context.rs' -print | head -n1)
test -n "$oracle_context"

bazel build --action_env=PATH //test/fixtures/tauri_codegen:codegen_probe >/dev/null
bazel_context="$repo_root/bazel-bin/test/fixtures/tauri_codegen/src-tauri/build_script.out_dir/tauri-build-context.rs"

python3 - "$oracle_context" "$bazel_context" <<'PY'
import pathlib
import re
import sys

def normalize(text: str) -> tuple[str, str]:
    authority = re.search(r':: tauri :: runtime_authority ! \(\{.*?\}\)', text, re.S)
    assets = re.search(r'inner\s*\(\s*\{\s*.*?EmbeddedAssets\s*::\s*new\s*\(.*?\)\s*\}\s*\)', text, re.S)
    if not authority:
        raise SystemExit("failed to locate runtime authority macro")
    if not assets:
        raise SystemExit("failed to locate embedded assets expression")
    normalize = lambda value: re.sub(r"\s+", " ", value).strip()
    return normalize(authority.group(0)), normalize(assets.group(0))

oracle = normalize(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
bazel = normalize(pathlib.Path(sys.argv[2]).read_text(encoding="utf-8"))

if oracle != bazel:
    raise SystemExit(
        "context runtime shape comparison failed\n"
        f"expected: {oracle!r}\n"
        f"actual:   {bazel!r}"
    )
PY

echo "context runtime shape comparison passed"
```

- [ ] **Step 2: Run the new oracle to verify it passes before replacement**

Run: `./test/compare_context_runtime_shape.sh`
Expected: `PASS`

- [ ] **Step 3: Commit the new runtime-shape oracle**

```bash
git add test/compare_context_runtime_shape.sh
git commit -m "test: add context runtime shape oracle"
```

### Task 4: Replace Context Assembly in the Bazel Context Tool

**Files:**
- Modify: `tools/tauri_context_codegen/src/main.rs`
- Modify if needed: `tools/tauri_context_codegen/Cargo.toml`
- Modify if needed: `tools/tauri_context_codegen/BUILD.bazel`
- Test:
  - `./test/compare_context_runtime_shape.sh`
  - `./test/compare_full_codegen_context.sh`
  - `./test/validate_rules_rust_codegen_fixture.sh`

- [ ] **Step 1: Write the failing context-assembly change**

Replace:

```rust
let context = tauri_codegen::context_codegen(tauri_codegen::ContextData {
    dev: true,
    config: config_value,
    config_parent,
    root: quote!(::tauri),
    capabilities: None,
    assets: Some(embedded_assets),
    test: false,
})
.context("failed to generate Tauri build context")?;
```

with a repo-owned assembly call:

```rust
let context = generate_context(
    &config_value,
    &config_parent,
    embedded_assets,
    &acl_out_dir,
)
.context("failed to generate repo-owned Tauri build context")?;
```

and add a minimal skeleton:

```rust
fn generate_context(
    _config: &tauri_utils::config::Config,
    _config_parent: &Path,
    _embedded_assets: Expr,
    _acl_out_dir: &Path,
) -> Result<String> {
    bail!("repo-owned context generation not implemented")
}
```

- [ ] **Step 2: Run the runtime-shape oracle to verify it fails**

Run: `./test/compare_context_runtime_shape.sh`
Expected: `FAIL` because the repo-owned assembly is not implemented yet.

- [ ] **Step 3: Implement the smallest runtime-relevant context assembly**

Implement `generate_context(...)` so it:

- emits a context expression using the existing embedded-assets expression parser output
- preserves the runtime-authority macro seam consumed by the fixture/example
- preserves `with_config_parent(...)` and runtime-relevant build config semantics
- reads ACL side outputs only through explicit Bazel-managed files copied into `OUT_DIR`

Use the current normalized-oracle scripts as the acceptance surface. Do not attempt to replicate unused upstream formatting or unsupported semantics.

- [ ] **Step 4: Re-run the narrow runtime-shape oracle**

Run: `./test/compare_context_runtime_shape.sh`
Expected: `PASS`

- [ ] **Step 5: Re-run the broader fixture checks**

Run:

```bash
./test/compare_full_codegen_context.sh
./test/validate_rules_rust_codegen_fixture.sh
```

Expected: both `PASS`

- [ ] **Step 6: Commit the context-assembly replacement**

```bash
git add tools/tauri_context_codegen/src/main.rs tools/tauri_context_codegen/Cargo.toml tools/tauri_context_codegen/BUILD.bazel
git commit -m "feat: own context assembly semantics"
```

### Task 5: Remove Active Upstream `tauri-codegen` Usage from the Bazel Release Path

**Files:**
- Modify: `tools/tauri_context_codegen/Cargo.toml`
- Modify: `tools/tauri_context_codegen/BUILD.bazel`
- Modify if needed: `private/upstream_context_oracle.bzl`
- Test:
  - `./test/compare_context_config_normalization.sh`
  - `./test/compare_context_runtime_shape.sh`
  - `./test/compare_context_build_config.sh`
  - `./test/compare_full_codegen_context.sh`

- [ ] **Step 1: Remove the upstream `tauri-codegen` dependency from the context tool**

Edit `tools/tauri_context_codegen/Cargo.toml` so the remaining compile-time tool dependencies no longer include `tauri-codegen`.

- [ ] **Step 2: Build the context tool to verify dependency closure**

Run: `bazel build //tools/tauri_context_codegen:tauri_context_codegen_exec`
Expected: `PASS`

- [ ] **Step 3: Re-run the seam and fixture checks**

Run:

```bash
./test/compare_context_config_normalization.sh
./test/compare_context_runtime_shape.sh
./test/compare_context_build_config.sh
./test/compare_full_codegen_context.sh
```

Expected: all `PASS`

- [ ] **Step 4: Commit the active-path upstream removal**

```bash
git add tools/tauri_context_codegen/Cargo.toml tools/tauri_context_codegen/BUILD.bazel private/upstream_context_oracle.bzl
git commit -m "feat: remove active tauri-codegen dependency"
```

### Task 6: Run the Full Verification Matrix on the Repo-Owned Path

**Files:**
- Modify only if verification exposes regressions:
  - `tools/tauri_context_codegen/src/main.rs`
  - `tools/tauri_acl_prep/src/main.rs`
  - `private/upstream_context_oracle.bzl`
  - relevant `test/*.sh`

- [ ] **Step 1: Run the full verification matrix**

Run:

```bash
./test/validate_rules_rust_codegen_fixture.sh
./test/compare_context_config_normalization.sh
./test/compare_context_runtime_shape.sh
./test/compare_context_build_config.sh
./test/compare_full_codegen_context.sh
bash ./test/compare_acl_resolution.sh
bash ./test/compare_runtime_authority_resolution.sh
./test/validate_examples.sh
./test/compare_tauri_parity.sh
```

Expected: all commands `PASS`

- [ ] **Step 2: Confirm the active Bazel release path no longer uses upstream compile-time crates**

Run:

```bash
rg -n "tauri_codegen::|tauri_build::try_build|tauri_build::Attributes::new\\(\\)\\.codegen" \
  tools/tauri_context_codegen \
  tools/tauri_acl_prep \
  private \
  examples/tauri_with_vite/app/src-tauri \
  test/fixtures/tauri_codegen/src-tauri
```

Expected:

- no active-path matches under `tools/tauri_context_codegen`, `tools/tauri_acl_prep`, `private`, or `examples/tauri_with_vite/app/src-tauri`
- fixture-only oracle references may remain where they are explicitly part of the upstream comparison surface

- [ ] **Step 3: Commit any final verification-only fixes**

```bash
git add -A
git commit -m "chore: finish semantic bazelfication cutover"
```
