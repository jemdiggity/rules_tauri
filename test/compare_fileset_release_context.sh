#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$repo_root"

path_for() {
  bazel cquery --output=starlark --starlark:expr='target.files.to_list()[0].path' "$1"
}

bazel build --action_env=PATH \
  //test/fixtures/tauri_codegen/src-tauri:full_context_rust \
  //test/fixtures/tauri_codegen/src-tauri:full_context_rust_fileset \
  //test/fixtures/tauri_codegen/src-tauri:_upstream_build_script_acl_prep \
  //test/fixtures/tauri_codegen/src-tauri:_upstream_build_script_fileset_acl_prep

context_dir="$repo_root/$(path_for //test/fixtures/tauri_codegen/src-tauri:full_context_rust)"
context_fileset="$repo_root/$(path_for //test/fixtures/tauri_codegen/src-tauri:full_context_rust_fileset)"
python3 - "$context_dir" "$context_fileset" "$repo_root/test" <<'PY'
import pathlib
import sys

sys.path.insert(0, sys.argv[3])

from compare_context_oracle_utils import (  # noqa: E402
    extract_build_block,
    extract_config_parent_arg,
    normalize_paths,
)

base_text = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
fileset_text = pathlib.Path(sys.argv[2]).read_text(encoding="utf-8")

base = (
    normalize_paths(extract_build_block(base_text)),
    normalize_paths(extract_config_parent_arg(base_text)),
)
fileset = (
    normalize_paths(extract_build_block(fileset_text)),
    normalize_paths(extract_config_parent_arg(fileset_text)),
)

if base != fileset:
    raise SystemExit(
        "fileset release context diverged from directory-based context\n"
        f"expected: {base!r}\n"
        f"actual:   {fileset!r}\n"
    )
PY

acl_dir="$repo_root/$(path_for //test/fixtures/tauri_codegen/src-tauri:_upstream_build_script_acl_prep)"
acl_fileset="$repo_root/$(path_for //test/fixtures/tauri_codegen/src-tauri:_upstream_build_script_fileset_acl_prep)"

cmp -s "$acl_dir/acl-manifests.json" "$acl_fileset/acl-manifests.json"
cmp -s "$acl_dir/capabilities.json" "$acl_fileset/capabilities.json"

echo "fileset release context comparison passed"
