#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
fixture_src_tauri="$repo_root/test/fixtures/tauri_codegen/src-tauri"
fixture_dist="$repo_root/test/fixtures/tauri_codegen/dist"
cd "$repo_root"

write_oracle_build_rs() {
    cat >"$1" <<'EOF'
fn main() {
    let attributes = tauri_build::Attributes::new().codegen(tauri_build::CodegenContext::new());
    tauri_build::try_build(attributes).expect("failed to generate Tauri build context");
}
EOF
}

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

oracle_root="$tmpdir/oracle"
mkdir -p "$oracle_root"
cp -R "$fixture_src_tauri" "$oracle_root/src-tauri"
cp -R "$fixture_dist" "$oracle_root/dist"
write_oracle_build_rs "$oracle_root/src-tauri/build.rs"

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

BUILD_MARKER = "build : :: tauri :: utils :: config :: BuildConfig {"
CONFIG_PARENT_MARKER = "with_config_parent"


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


def extract_build_block(text: str) -> str:
    start = text.find(BUILD_MARKER)
    if start < 0:
        raise SystemExit("failed to locate BuildConfig block")
    brace_start = text.find("{", start)
    return extract_balanced(text, brace_start, "{", "}")


def extract_config_parent_arg(text: str) -> str:
    start = text.find(CONFIG_PARENT_MARKER)
    if start < 0:
        raise SystemExit("failed to locate with_config_parent call")
    paren_start = text.find("(", start)
    call = extract_balanced(text, paren_start, "(", ")")
    return call[1:-1]


def normalize(fragment: str) -> str:
    fragment = re.sub(r'"[^"]*/src-tauri"', '"$MANIFEST_DIR"', fragment)
    fragment = re.sub(r"\s+", " ", fragment).strip()
    return fragment


oracle_text = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
bazel_text = pathlib.Path(sys.argv[2]).read_text(encoding="utf-8")

oracle = (
    normalize(extract_build_block(oracle_text)),
    normalize(extract_config_parent_arg(oracle_text)),
)
bazel = (
    normalize(extract_build_block(bazel_text)),
    normalize(extract_config_parent_arg(bazel_text)),
)

if oracle != bazel:
    raise SystemExit(
        "context config normalization comparison failed\n"
        f"expected: {oracle!r}\n"
        f"actual:   {bazel!r}"
    )
PY

echo "context config normalization comparison passed"
