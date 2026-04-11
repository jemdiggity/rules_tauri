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
compare_context_prepare_oracle_src_tauri "$oracle_root/src-tauri"

(
    cd "$oracle_root/src-tauri"
    CARGO_TARGET_DIR="$tmpdir/target" cargo build --quiet >/dev/null
)

oracle_context=$(compare_context_find_unique_context "$tmpdir/target/debug/build")
test -n "$oracle_context"

bazel build --action_env=PATH //test/fixtures/tauri_codegen:codegen_probe >/dev/null
bazel_context="$repo_root/bazel-bin/test/fixtures/tauri_codegen/src-tauri/build_script.out_dir/tauri-build-context.rs"

python3 - "$oracle_context" "$tmpdir/target/debug/build" "$bazel_context" "$repo_root/bazel-bin/test/fixtures/tauri_codegen/src-tauri/build_script.out_dir" <<'PY'
import pathlib
import plistlib
import re
import sys


def plist_hash(context_text: str) -> str:
    match = re.search(
        r'embed_info_plist ! .*?"([0-9a-f]{64})"',
        context_text,
        re.S,
    )
    if not match:
        raise SystemExit("failed to locate embed_info_plist hash")
    return match.group(1)


def find_plist_payload(root: pathlib.Path, hash_name: str) -> pathlib.Path:
    direct = root / hash_name
    if direct.exists():
        return direct

    matches = list(root.rglob(hash_name))
    if len(matches) != 1:
        raise SystemExit(
            f"expected exactly one plist payload named {hash_name} under {root}, found {len(matches)}"
        )
    return matches[0]


def load_plist(context_path: pathlib.Path, out_dir: pathlib.Path) -> dict:
    context_text = context_path.read_text(encoding="utf-8")
    payload = find_plist_payload(out_dir, plist_hash(context_text))
    return plistlib.loads(payload.read_bytes())


oracle = load_plist(pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]))
bazel = load_plist(pathlib.Path(sys.argv[3]), pathlib.Path(sys.argv[4]))

if oracle != bazel:
    raise SystemExit(
        "context plist emission comparison failed\n"
        f"expected: {oracle!r}\n"
        f"actual:   {bazel!r}"
    )
PY

echo "context plist emission comparison passed"
