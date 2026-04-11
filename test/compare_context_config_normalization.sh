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
import sys

sys.path.insert(0, str(pathlib.Path.cwd() / "test"))
from compare_context_oracle_utils import (  # noqa: E402
    extract_build_block,
    extract_config_parent_arg,
    normalize_paths,
)


def extract_product_name(text: str) -> str:
    marker = 'product_name : :: core :: option :: Option :: Some ("'
    start = text.find(marker)
    if start < 0:
        raise SystemExit("failed to locate product_name")
    start += len(marker)
    end = text.find('" . into ())', start)
    if end < 0:
        raise SystemExit("failed to terminate product_name")
    return text[start:end]


oracle_text = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
bazel_text = pathlib.Path(sys.argv[2]).read_text(encoding="utf-8")

oracle = (
    normalize_paths(extract_build_block(oracle_text)),
    normalize_paths(extract_config_parent_arg(oracle_text)),
    extract_product_name(oracle_text),
)
bazel = (
    normalize_paths(extract_build_block(bazel_text)),
    normalize_paths(extract_config_parent_arg(bazel_text)),
    extract_product_name(bazel_text),
)

if oracle != bazel:
    raise SystemExit(
        "context config normalization comparison failed\n"
        f"expected: {oracle!r}\n"
        f"actual:   {bazel!r}"
    )
PY

echo "context config normalization comparison passed"
