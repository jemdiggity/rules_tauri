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


def extract_embedded_assets_call(text: str) -> str:
    marker = "EmbeddedAssets :: new ("
    start = text.find(marker)
    if start < 0:
        raise SystemExit("failed to locate EmbeddedAssets::new call")
    paren_start = text.find("(", start)
    return extract_balanced(text, paren_start, "(", ")")


def normalize_runtime(fragment: str) -> str:
    fragment = re.sub(r"# \[cfg \(debug_assertions\)\]\s*", "", fragment)
    fragment = re.sub(r"\s+", " ", fragment).strip()
    return fragment


def parse_csp_hashes(fragment: str) -> list[tuple[str, str]]:
    return sorted(
        re.findall(
            r"CspHash\s*::\s*(Script|Style)\s*\(\s*(\"'sha256-[^\"]+\")\s*\)",
            fragment,
        )
    )


def normalize_assets(fragment: str) -> tuple[
    list[str], list[tuple[str, str]], list[tuple[str, list[tuple[str, str]]]]
]:
    asset_keys = sorted(re.findall(r'"(/[^"]+)"\s*=>\s*(?:b"|{)', fragment))
    global_hashes = parse_csp_hashes(fragment)

    html_hash_entries = []
    for path, hashes in re.findall(r'"(/[^"]+)"\s*=>\s*&\s*(\[[^\]]*\])', fragment, re.S):
        html_hash_entries.append((path, parse_csp_hashes(hashes)))

    return asset_keys, global_hashes, sorted(html_hash_entries)


oracle_text = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
bazel_text = pathlib.Path(sys.argv[2]).read_text(encoding="utf-8")

oracle = (
    normalize_runtime(extract_runtime_authority(oracle_text)),
    normalize_assets(extract_embedded_assets_call(oracle_text)),
)
bazel = (
    normalize_runtime(extract_runtime_authority(bazel_text)),
    normalize_assets(extract_embedded_assets_call(bazel_text)),
)

if oracle != bazel:
    raise SystemExit(
        "context runtime shape comparison failed\n"
        f"expected: {oracle!r}\n"
        f"actual:   {bazel!r}"
    )
PY

echo "context runtime shape comparison passed"
