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

oracle_out_dir=$(find "$tmpdir/target/debug/build" -path '*/out/acl-manifests.json' -print | head -n1 | xargs dirname)
test -n "$oracle_out_dir"

bazel build --action_env=PATH //test/fixtures/tauri_codegen:codegen_probe >/dev/null
bazel_out_dir="$repo_root/bazel-bin/test/fixtures/tauri_codegen/src-tauri/build_script.out_dir"

python3 - "$oracle_out_dir" "$bazel_out_dir" <<'PY'
import json
import pathlib
import sys

oracle = pathlib.Path(sys.argv[1])
bazel = pathlib.Path(sys.argv[2])

for name in ("acl-manifests.json", "capabilities.json"):
    expected = json.loads((oracle / name).read_text())
    actual = json.loads((bazel / name).read_text())
    if expected != actual:
        raise SystemExit(
            f"ACL resolution comparison failed for {name}\n"
            f"expected: {expected!r}\n"
            f"actual:   {actual!r}"
        )
PY

echo "acl resolution comparison passed"
