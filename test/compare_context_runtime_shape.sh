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
mkdir -p "$oracle_root"
cp -R "$fixture_src_tauri" "$oracle_root/src-tauri"
cp -R "$fixture_dist" "$oracle_root/dist"
compare_context_write_oracle_build_rs "$oracle_root/src-tauri/build.rs"

(
    cd "$oracle_root/src-tauri"
    CARGO_TARGET_DIR="$tmpdir/target" cargo build --quiet >/dev/null
)

oracle_context=$(compare_context_find_unique_context "$tmpdir/target/debug/build")
test -n "$oracle_context"

bazel build --action_env=PATH //test/fixtures/tauri_codegen:codegen_probe >/dev/null
bazel_context="$repo_root/bazel-bin/test/fixtures/tauri_codegen/src-tauri/build_script.out_dir/tauri-build-context.rs"

python3 - "$oracle_context" "$bazel_context" <<'PY'
import pathlib
import re
import sys


def extract_balanced(text: str, start: int, open_ch: str, close_ch: str) -> str:
    depth = 0
    for idx in range(start, len(text)):
        ch = text[idx]
        if ch == open_ch:
            depth += 1
        elif ch == close_ch:
            depth -= 1
            if depth == 0:
                return text[start:idx + 1]
    raise SystemExit("unterminated balanced block")


def extract_runtime_authority(text: str) -> str:
    marker = "runtime_authority ! ("
    start = text.find(marker)
    if start < 0:
        raise SystemExit("failed to locate runtime_authority macro")
    brace_start = text.find("{", start)
    return extract_balanced(text, brace_start, "{", "}")


def extract_embedded_assets(text: str) -> str:
    marker = "inner ("
    start = text.rfind(marker)
    if start < 0:
        raise SystemExit("failed to locate embedded assets expression")
    paren_start = text.find("(", start)
    return extract_balanced(text, paren_start, "(", ")")


def normalize_runtime(fragment: str) -> str:
    fragment = re.sub(r"# \[cfg \(debug_assertions\)\]\s*", "", fragment)
    fragment = re.sub(r"\s+", " ", fragment).strip()
    return fragment


def normalize_assets(fragment: str) -> str:
    if "EmbeddedAssets :: new (" not in fragment:
        raise SystemExit("failed to locate EmbeddedAssets::new call")
    return "inner({$EMBEDDED_ASSETS})"


oracle_text = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
bazel_text = pathlib.Path(sys.argv[2]).read_text(encoding="utf-8")

oracle = (
    normalize_runtime(extract_runtime_authority(oracle_text)),
    normalize_assets(extract_embedded_assets(oracle_text)),
)
bazel = (
    normalize_runtime(extract_runtime_authority(bazel_text)),
    normalize_assets(extract_embedded_assets(bazel_text)),
)

if oracle != bazel:
    raise SystemExit(
        "context runtime shape comparison failed\n"
        f"expected: {oracle!r}\n"
        f"actual:   {bazel!r}"
    )
PY

echo "context runtime shape comparison passed"
