# Bazel-Owned Embedded Assets Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the embedded-asset generation seam of Tauri compile-time behavior with Bazel-owned deterministic generation, while keeping the current Tauri runtime and end-to-end example working.

**Architecture:** Build this seam from the outside in. First add narrow fixtures for asset ordering and embedded Rust generation, then implement Bazel helpers that pass those seam comparisons, then wire the generated Rust into the isolated `tauri_codegen` fixture, and only after that reconnect the realistic example. The normal `tauri_with_vite` example should remain a consumer, not the first debug target.

**Tech Stack:** Bazel, Starlark, Python helper tools, `rules_rust`, local Tauri source as oracle, shell validation

---

### Task 1: Add A Narrow Asset-Ordering Fixture

**Files:**
- Create: `test/fixtures/embedded_assets_order/BUILD.bazel`
- Create: `test/fixtures/embedded_assets_order/assets/index.html`
- Create: `test/fixtures/embedded_assets_order/assets/assets/app.js`
- Create: `test/fixtures/embedded_assets_order/assets/assets/app.css`
- Create: `test/fixtures/embedded_assets_order/assets/images/logo.svg`
- Create: `test/fixtures/embedded_assets_order/oracle.py`
- Create: `test/compare_embedded_assets_order.sh`
- Modify: `tools/BUILD.bazel`

- [ ] **Step 1: Add a minimal mixed asset tree**

Create the fixture files listed above so the ordering seam covers:

```text
index.html
assets/app.js
assets/app.css
images/logo.svg
```

with simple deterministic contents.

- [ ] **Step 2: Add an upstream-order oracle script**

Create `test/fixtures/embedded_assets_order/oracle.py` that:

- walks the asset tree the same way upstream Tauri currently does for directory input
- normalizes each file to the public asset key shape
- writes a JSON array of ordered asset keys to stdout

The script must keep the output explicit and inspectable:

```python
#!/usr/bin/env python3
import json
from pathlib import Path

root = Path(__file__).resolve().parent / "assets"
ordered = [
    # compute and append normalized keys here
]
print(json.dumps(ordered, indent=2))
```

- [ ] **Step 3: Add a failing comparison script**

Create `test/compare_embedded_assets_order.sh` that initially expects a Bazel target to exist:

```sh
#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
fixture_dir="$repo_root/test/fixtures/embedded_assets_order"

expected=$(mktemp)
actual=$(mktemp)
trap 'rm -f "$expected" "$actual"' EXIT

python3 "$fixture_dir/oracle.py" >"$expected"
bazel build //test/fixtures/embedded_assets_order:asset_manifest >/dev/null
cp "$repo_root/bazel-bin/test/fixtures/embedded_assets_order/asset_manifest.json" "$actual"

diff -u "$expected" "$actual"
echo "embedded asset ordering comparison passed"
```

- [ ] **Step 4: Run the seam comparison to verify it fails for the right reason**

Run: `./test/compare_embedded_assets_order.sh`
Expected: FAIL because `//test/fixtures/embedded_assets_order:asset_manifest` does not exist yet

- [ ] **Step 5: Commit**

```bash
git add test/fixtures/embedded_assets_order tools/BUILD.bazel test/compare_embedded_assets_order.sh
git commit -m "test: add embedded asset ordering seam fixture"
```

### Task 2: Implement Deterministic Asset Manifest Generation

**Files:**
- Create: `tools/tauri_assets_manifest.py`
- Modify: `tools/BUILD.bazel`
- Modify: `test/fixtures/embedded_assets_order/BUILD.bazel`

- [ ] **Step 1: Add a Bazel-executable helper for asset manifests**

Create `tools/tauri_assets_manifest.py` that:

- accepts one input directory and one output file
- walks the tree deterministically
- emits a JSON array of normalized asset keys

The helper should use explicit sorting:

```python
files = sorted(path for path in root.rglob("*") if path.is_file())
```

and write:

```python
json.dump(asset_keys, output, indent=2)
output.write("\n")
```

- [ ] **Step 2: Expose the helper in Bazel**

Add it to `tools/BUILD.bazel` as an exported executable input.

- [ ] **Step 3: Add `asset_manifest` target in the fixture BUILD**

Create a build target at `//test/fixtures/embedded_assets_order:asset_manifest` that:

- takes the fixture asset tree
- invokes `tools/tauri_assets_manifest.py`
- produces `asset_manifest.json`

- [ ] **Step 4: Run the ordering seam comparison**

Run: `./test/compare_embedded_assets_order.sh`
Expected: PASS with exact JSON equality

- [ ] **Step 5: Commit**

```bash
git add tools/tauri_assets_manifest.py tools/BUILD.bazel test/fixtures/embedded_assets_order/BUILD.bazel
git commit -m "feat: generate deterministic tauri asset manifests"
```

### Task 3: Add An Embedded Rust Generation Fixture

**Files:**
- Create: `test/fixtures/embedded_assets_rust/BUILD.bazel`
- Create: `test/fixtures/embedded_assets_rust/assets/index.html`
- Create: `test/fixtures/embedded_assets_rust/assets/assets/app.js`
- Create: `test/fixtures/embedded_assets_rust/assets/assets/app.css`
- Create: `test/fixtures/embedded_assets_rust/oracle_build.rs`
- Create: `test/compare_embedded_assets_rust.sh`

- [ ] **Step 1: Add a minimal embedded-assets fixture**

Create a tiny asset tree under `test/fixtures/embedded_assets_rust/assets` with fixed contents suitable for byte comparison.

- [ ] **Step 2: Add an upstream oracle build script**

Create `test/fixtures/embedded_assets_rust/oracle_build.rs` that:

- invokes the same upstream `tauri-codegen` embedded-assets path
- writes a generated Rust source file to a known output location

The oracle only needs to exercise embedded assets, not full context generation.

- [ ] **Step 3: Add a failing comparison script**

Create `test/compare_embedded_assets_rust.sh` that:

- builds the upstream oracle output
- builds a Bazel target `//test/fixtures/embedded_assets_rust:embedded_assets_rust`
- compares the two outputs structurally

Initial shape:

```sh
#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)

bazel build //test/fixtures/embedded_assets_rust:embedded_assets_rust >/dev/null

# compare generated Rust output here
```

- [ ] **Step 4: Run the comparison to verify it fails because the Bazel target is missing**

Run: `./test/compare_embedded_assets_rust.sh`
Expected: FAIL because the embedded-assets Rust target is not implemented yet

- [ ] **Step 5: Commit**

```bash
git add test/fixtures/embedded_assets_rust test/compare_embedded_assets_rust.sh
git commit -m "test: add embedded assets rust seam fixture"
```

### Task 4: Implement Deterministic Embedded Rust Source Generation

**Files:**
- Create: `tools/tauri_embedded_assets_rust.py`
- Modify: `tools/BUILD.bazel`
- Modify: `test/fixtures/embedded_assets_rust/BUILD.bazel`

- [ ] **Step 1: Add a helper that turns an asset manifest plus asset tree into Rust source**

Create `tools/tauri_embedded_assets_rust.py` that:

- reads the asset tree
- sorts assets deterministically
- emits Rust source containing embedded byte literals

The generated file should be explicit and stable:

```rust
pub const EMBEDDED_ASSETS: &[(&str, &[u8])] = &[
    ("/assets/app.css", b"..."),
    ("/assets/app.js", b"..."),
    ("/index.html", b"..."),
];
```

Do not depend on host temp paths, `include_bytes!`, or random identifiers in this phase.

- [ ] **Step 2: Add a Bazel target for the Rust generation seam**

Create `//test/fixtures/embedded_assets_rust:embedded_assets_rust` so it produces a generated Rust file from the fixture assets.

- [ ] **Step 3: Update the comparison script to compare semantics**

The comparison should verify:

- the same ordered asset keys
- the same embedded bytes for each asset

It does not need byte-for-byte textual identity with upstream if upstream ordering/text formatting differs.

- [ ] **Step 4: Run the embedded Rust seam comparison**

Run: `./test/compare_embedded_assets_rust.sh`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add tools/tauri_embedded_assets_rust.py tools/BUILD.bazel test/fixtures/embedded_assets_rust/BUILD.bazel test/compare_embedded_assets_rust.sh
git commit -m "feat: generate tauri embedded asset rust source"
```

### Task 5: Wire Bazel-Generated Embedded Assets Into The Isolated Codegen Fixture

**Files:**
- Modify: `test/fixtures/tauri_codegen/BUILD.bazel`
- Modify: `test/fixtures/tauri_codegen/src-tauri/BUILD.bazel`
- Modify: `test/fixtures/tauri_codegen/src-tauri/build.rs`
- Modify: `test/validate_rules_rust_codegen_fixture.sh`

- [ ] **Step 1: Add a failing integration check**

Extend the existing codegen fixture path so it expects Bazel-generated embedded asset source to be available.

Run: `./test/validate_rules_rust_codegen_fixture.sh`
Expected: FAIL because the fixture still relies on upstream embedded-assets generation

- [ ] **Step 2: Thread the generated Rust source into the fixture build**

Modify the fixture targets so the Bazel-generated embedded asset Rust source is available to the crate build.

Keep the fixture scope narrow:

- do not replace full ACL generation
- do not replace full context generation
- only replace the embedded asset source seam

- [ ] **Step 3: Update the fixture build script or supporting code to consume the generated source**

Modify `test/fixtures/tauri_codegen/src-tauri/build.rs` only enough to switch the embedded-asset source seam while preserving the rest of the current fixture behavior.

- [ ] **Step 4: Run the isolated fixture validation**

Run: `./test/validate_rules_rust_codegen_fixture.sh`
Expected: `rules_rust tauri codegen fixture passed`

- [ ] **Step 5: Commit**

```bash
git add test/fixtures/tauri_codegen test/validate_rules_rust_codegen_fixture.sh
git commit -m "feat: use bazel embedded assets in codegen fixture"
```

### Task 6: Reconnect The Real Example And Re-Run Repo Verification

**Files:**
- Modify: `examples/tauri_with_vite/app/src-tauri/BUILD.bazel`
- Modify: `examples/tauri_with_vite/app/src-tauri/build.rs`
- Modify: `examples/tauri_with_vite/README.md`
- Modify: `docs/testing.md`

- [ ] **Step 1: Keep the real example pointed at Bazel-generated frontend assets**

Reconnect the realistic example so the Bazel-generated embedded-assets seam is used in the `tauri_with_vite` app build, not just in the isolated fixture.

- [ ] **Step 2: Build the real example**

Run: `bazel build //examples/tauri_with_vite:app_arm64`
Expected: PASS

- [ ] **Step 3: Verify embedded assets are still present**

Run: `strings bazel-bin/examples/tauri_with_vite/app_arm64.app/Contents/MacOS/tauri-with-vite | rg '/assets/index-|/vite.svg'`
Expected: both markers present

- [ ] **Step 4: Run repository verification**

Run:

```sh
./test/validate_examples.sh
./test/validate_rules_rust_codegen_fixture.sh
./test/compare_embedded_assets_order.sh
./test/compare_embedded_assets_rust.sh
./test/compare_tauri_parity.sh
```

Expected:

```text
rules_tauri example validation passed
rules_rust tauri codegen fixture passed
embedded asset ordering comparison passed
embedded assets rust comparison passed
tauri parity comparison passed
```

- [ ] **Step 5: Update docs to reflect the new seam ownership**

Document that:

- Bazel now owns embedded asset generation for the example path
- Tauri remains runtime plus unreplaced compile-time seams

- [ ] **Step 6: Commit**

```bash
git add examples/tauri_with_vite/app/src-tauri/BUILD.bazel examples/tauri_with_vite/app/src-tauri/build.rs examples/tauri_with_vite/README.md docs/testing.md test/compare_embedded_assets_order.sh test/compare_embedded_assets_rust.sh
git commit -m "feat: move tauri embedded assets seam into bazel"
```
