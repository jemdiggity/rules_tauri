#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
fixture_src_tauri="$repo_root/test/fixtures/tauri_codegen/src-tauri"
fixture_dist="$repo_root/test/fixtures/tauri_codegen/dist"
cd "$repo_root"
. "$repo_root/test/compare_context_common.sh"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

oracle_root="$tmpdir/oracle"
compare_context_stage_oracle_workspace "$fixture_src_tauri" "$fixture_dist" "$oracle_root"
compare_context_build_oracle_workspace "$oracle_root" "$tmpdir/target"

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
