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

oracle_context=$(find "$tmpdir/target/debug/build" -path '*/out/tauri-build-context.rs' -print | head -n1)
test -n "$oracle_context"

bazel build --action_env=PATH //test/fixtures/tauri_codegen:codegen_probe >/dev/null
bazel_context="$repo_root/bazel-bin/test/fixtures/tauri_codegen/src-tauri/build_script.out_dir/tauri-build-context.rs"

python3 - "$oracle_context" "$bazel_context" <<'PY'
import pathlib
import re
import sys

MARKER = ":: tauri :: utils :: acl :: resolved :: Resolved {"


def extract_resolved_block(path: pathlib.Path) -> str:
    text = path.read_text(encoding="utf-8")
    start = text.find(MARKER)
    if start < 0:
        raise SystemExit(f"failed to locate resolved ACL block in {path}")
    brace_start = text.find("{", start)
    depth = 0
    for idx in range(brace_start, len(text)):
        ch = text[idx]
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                return text[start:idx + 1]
    raise SystemExit(f"unterminated resolved ACL block in {path}")

def normalize(block: str) -> str:
    # Bazel generates debug-only metadata behind a cfg wrapper so fastbuild
    # still compiles; upstream cargo debug emits the same metadata unwrapped.
    block = block.replace("# [cfg (debug_assertions)] ", "")
    block = re.sub(r",\s*([}\]])", r" \1", block)
    block = re.sub(r"\s+", " ", block).strip()
    return block

oracle = normalize(extract_resolved_block(pathlib.Path(sys.argv[1])))
bazel = normalize(extract_resolved_block(pathlib.Path(sys.argv[2])))
if oracle != bazel:
    raise SystemExit(
        "runtime authority ACL resolution comparison failed\n"
        f"expected: {oracle!r}\n"
        f"actual:   {bazel!r}"
    )
PY

echo "runtime authority ACL resolution comparison passed"
