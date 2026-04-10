#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
fixture_dir="$repo_root/test/fixtures/embedded_assets_rust"
cd "$repo_root"

if [ "${TAURI_CODEGEN_REPO:-}" = "" ]; then
    echo "TAURI_CODEGEN_REPO must point to a local Tauri checkout" >&2
    exit 1
fi
tauri_repo="$TAURI_CODEGEN_REPO"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

expected_crate="$tmpdir/oracle"
mkdir -p "$expected_crate/src"
cp "$fixture_dir/oracle_compressed_build.rs" "$expected_crate/oracle_build.rs"
cp "$fixture_dir/oracle_Cargo.lock" "$expected_crate/Cargo.lock"
mkdir -p "$expected_crate/assets"
cp -R "$fixture_dir/assets/." "$expected_crate/assets/"
cat >"$expected_crate/Cargo.toml" <<EOF
[package]
name = "embedded_assets_compression_oracle"
version = "0.0.0"
edition = "2021"
build = "oracle_build.rs"

[build-dependencies]
quote = "1"
regex = "1"
tauri-codegen = { path = "$tauri_repo/crates/tauri-codegen", features = ["compression"] }
tauri-utils = { path = "$tauri_repo/crates/tauri-utils" }
EOF
cat >"$expected_crate/src/lib.rs" <<'EOF'
pub fn placeholder() {}
EOF

bazel build --action_env=PATH //test/fixtures/embedded_assets_rust:embedded_assets_compressed_rust >/dev/null

(
    cd "$expected_crate"
    CARGO_TARGET_DIR="$tmpdir/target" cargo build --quiet >/dev/null
)

expected_rust="$expected_crate/embedded_assets_compressed.oracle.rs"
actual_rust="$repo_root/bazel-bin/test/fixtures/embedded_assets_rust/embedded_assets_compressed_rust.rs"

python3 - "$expected_rust" "$actual_rust" <<'PY'
import pathlib
import re
import sys


def decode_rust_string(token: str) -> str:
    assert token.startswith('"') and token.endswith('"')
    i = 1
    result = []
    while i < len(token) - 1:
        ch = token[i]
        if ch != "\\":
            result.append(ch)
            i += 1
            continue
        i += 1
        esc = token[i]
        if esc == "\\":
            result.append("\\")
            i += 1
        elif esc == '"':
            result.append('"')
            i += 1
        elif esc == "n":
            result.append("\n")
            i += 1
        elif esc == "r":
            result.append("\r")
            i += 1
        elif esc == "t":
            result.append("\t")
            i += 1
        elif esc == "0":
            result.append("\0")
            i += 1
        elif esc == "u":
            assert token[i + 1] == "{"
            end = token.index("}", i + 2)
            result.append(chr(int(token[i + 2:end], 16)))
            i = end + 1
        else:
            raise ValueError(f"unsupported string escape \\{esc}")
    return "".join(result)


def decode_rust_byte_string(token: str) -> bytes:
    assert token.startswith('b"') and token.endswith('"')
    i = 2
    result = bytearray()
    while i < len(token) - 1:
        ch = token[i]
        if ch != "\\":
            result.append(ord(ch))
            i += 1
            continue
        i += 1
        esc = token[i]
        if esc == "\\":
            result.append(0x5C)
            i += 1
        elif esc == '"':
            result.append(0x22)
            i += 1
        elif esc == "n":
            result.append(0x0A)
            i += 1
        elif esc == "r":
            result.append(0x0D)
            i += 1
        elif esc == "t":
            result.append(0x09)
            i += 1
        elif esc == "0":
            result.append(0x00)
            i += 1
        elif esc == "x":
            result.append(int(token[i + 1:i + 3], 16))
            i += 3
        else:
            raise ValueError(f"unsupported byte escape \\{esc}")
    return bytes(result)


PAIR_RE = re.compile(
    r'^\s*\(\s*("(?:(?:\\.)|[^"])*")\s*,\s*(b"(?:(?:\\.)|[^"])*")\s*\),\s*$'
)


def parse_pairs(path: pathlib.Path) -> list[tuple[str, bytes]]:
    pairs = []
    for line in path.read_text(encoding="utf-8").splitlines():
        match = PAIR_RE.match(line)
        if not match:
            continue
        pairs.append(
            (
                decode_rust_string(match.group(1)),
                decode_rust_byte_string(match.group(2)),
            )
        )
    if not pairs:
        raise SystemExit(f"failed to parse embedded assets from {path}")
    return pairs


expected_pairs = parse_pairs(pathlib.Path(sys.argv[1]))
actual_pairs = parse_pairs(pathlib.Path(sys.argv[2]))
if expected_pairs != actual_pairs:
    raise SystemExit(
        "embedded assets compression comparison failed\n"
        f"expected: {expected_pairs!r}\n"
        f"actual:   {actual_pairs!r}"
    )
PY

echo "embedded assets compression comparison passed"
