#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
fixture_dir="$repo_root/test/fixtures/embedded_assets_transform"
cd "$repo_root"

if [ "${TAURI_CODEGEN_REPO:-}" = "" ]; then
    echo "TAURI_CODEGEN_REPO must point to a local Tauri checkout" >&2
    exit 1
fi
tauri_repo="$TAURI_CODEGEN_REPO"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

expected_crate="$tmpdir/oracle"
mkdir -p "$expected_crate/src" "$expected_crate/assets"
cp "$fixture_dir/oracle_build.rs" "$expected_crate/oracle_build.rs"
cp -R "$fixture_dir/assets/." "$expected_crate/assets/"
cat >"$expected_crate/Cargo.toml" <<EOF
[package]
name = "embedded-assets-transform-oracle"
version = "0.0.0"
edition = "2021"
build = "oracle_build.rs"

[build-dependencies]
base64 = "0.22"
serde_json = "1"
sha2 = "0.10"
tauri-utils = { path = "$tauri_repo/crates/tauri-utils", features = ["html-manipulation-2"] }
walkdir = "2"
EOF
cat >"$expected_crate/src/lib.rs" <<'EOF'
pub fn placeholder() {}
EOF

(
    cd "$expected_crate"
    CARGO_TARGET_DIR="$tmpdir/target" cargo build --quiet >/dev/null
)

expected_json="$expected_crate/embedded_assets_transform.oracle.json"
bazel build --action_env=PATH //test/fixtures/embedded_assets_transform:transformed_assets >/dev/null
actual_json="$repo_root/bazel-bin/test/fixtures/embedded_assets_transform/transformed_assets.json"

test -f "$expected_json"
test -f "$actual_json"

python3 - "$expected_json" "$actual_json" <<'PY'
import json
import pathlib
import sys

expected = json.loads(pathlib.Path(sys.argv[1]).read_text())
actual = json.loads(pathlib.Path(sys.argv[2]).read_text())
if expected != actual:
    raise SystemExit(
        "embedded assets transform comparison failed\n"
        f"expected: {expected!r}\n"
        f"actual:   {actual!r}"
    )
PY

echo "embedded assets transform comparison passed"
