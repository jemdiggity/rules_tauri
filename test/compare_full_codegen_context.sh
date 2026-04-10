#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
fixture_src_tauri="$repo_root/test/fixtures/tauri_codegen/src-tauri"
fixture_dist="$repo_root/test/fixtures/tauri_codegen/dist"
cd "$repo_root"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

oracle_root="$tmpdir/oracle"
mkdir -p "$oracle_root"
cp -R "$fixture_src_tauri" "$oracle_root/src-tauri"
cp -R "$fixture_dist" "$oracle_root/dist"

(
    cd "$oracle_root/src-tauri"
    CARGO_TARGET_DIR="$tmpdir/target" cargo build --quiet >/dev/null
)

oracle_context=$(find "$tmpdir/target/debug/build" -path '*/out/tauri-build-context.rs' -print | head -n1)
test -n "$oracle_context"

bazel build --action_env=PATH //test/fixtures/tauri_codegen:codegen_probe >/dev/null
bazel_context="$repo_root/bazel-bin/test/fixtures/tauri_codegen/src-tauri/build_script.out_dir/tauri-build-context.rs"

python3 - "$oracle_context" "$bazel_context" <<'PY'
import pathlib
import re
import sys


# Normalized seams:
# - embedded assets expression body
# - build.frontend_dist / with_config_parent path roots
# - runtime authority macro body
# - debug cfg wrappers and token formatting
def normalize_context(text: str) -> str:
    text = text.replace("# [cfg (debug_assertions)] ", "")
    text = text.replace("move | |", "move ||")
    text = re.sub(r",\s*([}\]])", r" \1", text)
    text = re.sub(
        r'OUT_DIR"\) , "/" , "[0-9a-f]{64}"',
        'OUT_DIR") , "/" , "$HASH"',
        text,
    )
    text = re.sub(r'"[^"]*/src-tauri"', '"$MANIFEST_DIR"', text)
    text = re.sub(
        r'build : :: tauri :: utils :: config :: BuildConfig \{.*?additional_watch_folders : Vec :: new \(\) \}',
        'build:BuildConfig{$BUILD}',
        text,
        flags=re.S,
    )
    text = re.sub(
        r'\. ?with_config_parent \([^\)]*\)',
        '.with_config_parent($MANIFEST_DIR)',
        text,
    )
    text = re.sub(
        r':: tauri :: runtime_authority ! \(\{.*?\}\)',
        '::tauri::runtime_authority!($AUTH)',
        text,
        flags=re.S,
    )
    text = re.sub(
        r'inner \(\{ .*? (?:EmbeddedAssets :: new \(.*?\)|const _ : & str = "RULES_TAURI_BAZEL_OWNED_EMBEDDED_ASSETS:[0-9a-f]+" ; EmbeddedAssets::new\(\$EMBEDDED\)) \}\)',
        'inner({$EMBEDDED_ASSETS})',
        text,
        flags=re.S,
    )
    text = re.sub(r"\s+", " ", text).strip()
    return text


oracle = normalize_context(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
bazel = normalize_context(pathlib.Path(sys.argv[2]).read_text(encoding="utf-8"))

if oracle != bazel:
    max_i = min(len(oracle), len(bazel))
    idx = 0
    while idx < max_i and oracle[idx] == bazel[idx]:
        idx += 1
    raise SystemExit(
        "full codegen context comparison failed\n"
        f"first diff index: {idx}\n"
        f"expected: {oracle[max(0, idx - 200):idx + 600]!r}\n"
        f"actual:   {bazel[max(0, idx - 200):idx + 600]!r}"
    )
PY

echo "full codegen context comparison passed"
