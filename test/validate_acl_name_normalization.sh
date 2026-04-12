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
acl_manifests="$acl_dir/acl-manifests.json"
resolved_capabilities="$acl_dir/capabilities.json"

grep -q '"opener:default"' "$staged_capability"
if grep -q '"plugin-opener:default"' "$staged_capability"; then
  echo "expected staged capability file to preserve authored opener prefix" >&2
  exit 1
fi
grep -q '"opener"' "$acl_manifests"
if grep -q '"plugin-opener"' "$acl_manifests"; then
  echo "expected ACL manifests to normalize plugin key to opener" >&2
  exit 1
fi
grep -q '"opener:default"' "$resolved_capabilities"
if grep -q '"plugin-opener:default"' "$resolved_capabilities"; then
  echo "expected resolved capabilities to preserve opener prefix" >&2
  exit 1
fi

echo "acl name normalization validation passed"
