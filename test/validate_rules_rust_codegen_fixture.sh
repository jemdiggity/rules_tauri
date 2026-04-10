#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$repo_root"

bazel build --action_env=PATH //test/fixtures/tauri_codegen:codegen_probe

probe_bin="$repo_root/bazel-bin/test/fixtures/tauri_codegen/codegen_probe_bin"

test -f "$probe_bin"
strings "$probe_bin" | grep -q "/assets/index-"
strings "$probe_bin" | grep -q "/vite.svg"

echo "rules_rust tauri codegen fixture passed"
