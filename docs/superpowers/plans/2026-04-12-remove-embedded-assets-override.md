# Remove Embedded Assets Override Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the public `embedded_assets_rust` override from `tauri_application()` so the high-level macro fully owns embedded asset generation.

**Architecture:** Keep the lower-level release/context rules unchanged and narrow only the public high-level macro contract. Add a focused negative test that proves Bazel analysis rejects the removed attribute, then update the macro, examples, and docs to match the new API.

**Tech Stack:** Bazel/Starlark, shell tests, existing example applications

---

### Task 1: Add a failing API-removal test

**Files:**
- Create: `test/fixtures/tauri_application_api/BUILD.bazel`
- Create: `test/api_rejects_embedded_assets_override.sh`

- [ ] **Step 1: Write the failing test fixture**

```starlark
package(default_visibility = ["//visibility:public"])

load("//tauri:defs.bzl", "tauri_application")

filegroup(
    name = "frontend_dist",
    srcs = ["index.html"],
)

filegroup(
    name = "cargo_srcs",
    srcs = ["Cargo.toml", "Cargo.lock", "tauri.conf.json", "src/main.rs", "src/lib.rs"],
)

filegroup(
    name = "tauri_build_data",
    srcs = ["tauri.conf.json"],
)

tauri_application(
    name = "bad_app",
    platform = "@platforms//host",
    target_triple = "aarch64-apple-darwin",
    bundle_id = "dev.rules_tauri.bad",
    product_name = "bad",
    frontend_dist = ":frontend_dist",
    embedded_assets_rust = ":frontend_dist",
    tauri_config = "tauri.conf.json",
    cargo_srcs = ":cargo_srcs",
    tauri_build_data = ":tauri_build_data",
    aliases = {},
    deps = [],
    proc_macro_deps = [],
)
```

- [ ] **Step 2: Write the failing shell test**

```sh
#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$repo_root"

if bazel build //test/fixtures/tauri_application_api:bad_app >out.txt 2>err.txt; then
  echo "expected analysis failure for removed embedded_assets_rust attribute" >&2
  exit 1
fi

grep -q "no such attribute 'embedded_assets_rust'" err.txt
```

- [ ] **Step 3: Run the test to verify RED**

Run: `./test/api_rejects_embedded_assets_override.sh`
Expected: FAIL because `tauri_application()` still accepts `embedded_assets_rust`

### Task 2: Remove the public macro override

**Files:**
- Modify: `tauri/defs.bzl`

- [ ] **Step 1: Remove the parameter from `tauri_application()`**

```starlark
def tauri_application(
        *,
        name,
        platform,
        target_triple,
        bundle_id,
        product_name,
        version = "",
        version_file = None,
        frontend_dist,
        tauri_config,
        cargo_srcs,
        tauri_build_data,
        aliases,
        deps,
        proc_macro_deps,
        ...):
```

- [ ] **Step 2: Inline macro-owned asset generation**

```starlark
    embedded_assets_rust_name = name + "_embedded_assets_rust"

    native.genrule(
        name = embedded_assets_rust_name,
        srcs = [":" + normalized_frontend_dist_name],
        tools = [
            "//tools/tauri_brotli_compress:tauri_brotli_compress_exec",
            "//tools/tauri_brotli_compress:tauri_transform_assets_exec",
            "//tools:tauri_embedded_assets_rust_exec",
        ],
        outs = [embedded_assets_rust_name + ".rs"],
        cmd = "$(execpath //tools:tauri_embedded_assets_rust_exec) --transformer $(execpath //tools/tauri_brotli_compress:tauri_transform_assets_exec) --compressor $(execpath //tools/tauri_brotli_compress:tauri_brotli_compress_exec) --compression-quality 2 $(location :%s) $@" % normalized_frontend_dist_name,
    )
```

- [ ] **Step 3: Pass the generated target into `tauri_rust_app()`**

```starlark
        embedded_assets_rust = ":" + embedded_assets_rust_name,
```

- [ ] **Step 4: Run the new test to verify GREEN**

Run: `./test/api_rejects_embedded_assets_override.sh`
Expected: PASS with Bazel analysis rejecting the removed attribute

### Task 3: Align docs and example validation

**Files:**
- Modify: `README.md`
- Modify: `examples/minimal_macos/README.md`
- Modify: `examples/tauri_with_vite/README.md`
- Modify: `test/validate_examples.sh`

- [ ] **Step 1: Remove language that advertises the override**

```md
For normal release apps, use `tauri_application(...)`. Its `frontend_dist` input can be either a directory-producing target or a file set, and the macro normalizes that input and generates the embedded-assets Rust source internally.
```

- [ ] **Step 2: Keep example validation focused on generated outputs, not a public override**

```sh
bazel build --action_env=PATH \
  //examples/minimal_macos:bundle_inputs_arm64 \
  ...
  //examples/minimal_macos/src-tauri:app_arm64_embedded_assets_rust \
  ...
```

- [ ] **Step 3: Run repo verification**

Run: `./test/api_rejects_embedded_assets_override.sh`
Expected: PASS

Run: `./test/validate_frontend_dist.sh`
Expected: PASS

Run: `./test/compare_fileset_release_context.sh`
Expected: PASS

Run: `./test/validate_examples.sh`
Expected: PASS
