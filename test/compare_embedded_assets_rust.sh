#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
fixture_dir="$repo_root/test/fixtures/embedded_assets_rust"
. "$repo_root/test/oracle_embedded_assets_common.sh"
cd "$repo_root"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

expected_crate="$tmpdir/oracle"
oracle_embedded_assets_prepare_crate \
    "$expected_crate" \
    "$fixture_dir" \
    "$fixture_dir/oracle_build.rs" \
    "embedded_assets_oracle" \
    "$fixture_dir/oracle_registry_Cargo.lock" \
    "tauri-codegen = \"=2.5.5\"
tauri-utils = \"=2.8.3\""

bazel build --action_env=PATH //test/fixtures/embedded_assets_rust:embedded_assets_rust >/dev/null

(
    cd "$expected_crate"
    CARGO_TARGET_DIR="$tmpdir/target" cargo build --quiet --locked >/dev/null
)

expected_rust="$expected_crate/embedded_assets_rust.oracle.rs"
actual_rust="$repo_root/bazel-bin/test/fixtures/embedded_assets_rust/embedded_assets_rust.rs"

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
    lines = path.read_text(encoding="utf-8").splitlines()
    pairs = []
    for line in lines:
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


expected_path = pathlib.Path(sys.argv[1])
actual_path = pathlib.Path(sys.argv[2])
expected_pairs = parse_pairs(expected_path)
actual_pairs = parse_pairs(actual_path)
if expected_pairs != actual_pairs:
    raise SystemExit(
        "embedded assets Rust comparison failed\n"
        f"expected: {expected_pairs!r}\n"
        f"actual:   {actual_pairs!r}"
    )
PY

echo "embedded assets Rust comparison passed"
