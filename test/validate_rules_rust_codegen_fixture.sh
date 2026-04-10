#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$repo_root"

bazel build --action_env=PATH //test/fixtures/tauri_codegen:codegen_probe

probe_bin="$repo_root/bazel-bin/test/fixtures/tauri_codegen/codegen_probe_bin"
dist_dir="$repo_root/bazel-bin/test/fixtures/tauri_codegen/dist"
generated_assets="$repo_root/bazel-bin/test/fixtures/tauri_codegen/embedded_assets_rust.rs"
context_rs="$repo_root/bazel-bin/test/fixtures/tauri_codegen/src-tauri/build_script.out_dir/tauri-build-context.rs"

test -f "$probe_bin"
test -d "$dist_dir"
test -f "$generated_assets"
test -f "$context_rs"
strings "$probe_bin" | grep -q "/assets/index-"
strings "$probe_bin" | grep -q "/vite.svg"
if grep -q "tauri-codegen-assets/" "$context_rs"; then
    echo "expected Bazel-owned embedded-assets seam, found upstream tauri-codegen-assets output" >&2
    exit 1
fi

python3 - "$dist_dir" "$generated_assets" "$context_rs" <<'PY'
import os
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
    r'("(?:(?:\\.)|[^"])*")\s*=>\s*(b"(?:(?:\\.)|[^"])*")',
)
FIXTURE_RE = re.compile(
    r'^\s*\(\s*("(?:(?:\\.)|[^"])*")\s*,\s*(b"(?:(?:\\.)|[^"])*")\s*\),\s*$'
)


def asset_key(root: pathlib.Path, path: pathlib.Path) -> str:
    relative = path.relative_to(root)
    parts = [
        os.fsencode(part).decode("utf-8", "replace")
        for part in relative.parts
    ]
    return "/" + "/".join(parts)


def raw_asset_path(root: pathlib.Path, path: pathlib.Path) -> bytes:
    relative = path.relative_to(root)
    return b"/".join(os.fsencode(part) for part in relative.parts)


def parse_dist_pairs(root: pathlib.Path) -> list[tuple[str, bytes]]:
    pairs = []
    for path in sorted(
        (path for path in root.rglob("*") if path.is_file()),
        key=lambda path: raw_asset_path(root, path),
    ):
        pairs.append((asset_key(root, path), path.read_bytes()))
    if not pairs:
        raise SystemExit(f"failed to read expected embedded assets from {root}")
    return pairs


def parse_generated_pairs(path: pathlib.Path) -> list[tuple[str, bytes]]:
    pairs = []
    for line in path.read_text(encoding="utf-8").splitlines():
        match = FIXTURE_RE.match(line)
        if match:
            pairs.append(
                (
                    decode_rust_string(match.group(1)),
                    decode_rust_byte_string(match.group(2)),
                )
            )
    if not pairs:
        raise SystemExit(f"failed to parse generated embedded assets from {path}")
    return pairs


def fnv1a64(data: bytes) -> int:
    hash_value = 0xCBF29CE484222325
    for byte in data:
        hash_value ^= byte
        hash_value = (hash_value * 0x100000001B3) & 0xFFFFFFFFFFFFFFFF
    return hash_value


def extract_marked_entries(text: str, marker: str) -> tuple[str, str]:
    marker_index = text.find(marker)
    if marker_index < 0:
        raise SystemExit("failed to locate embedded assets marker in generated context")

    phf_match = re.search(r'phf_map\s*!', text[marker_index:])
    if not phf_match:
        raise SystemExit("failed to locate phf_map! block after embedded assets marker")
    map_start = marker_index + phf_match.start()

    brace_start = text.find('{', map_start)
    depth = 0
    in_string = False
    escaped = False
    for index in range(brace_start, len(text)):
        char = text[index]
        if in_string:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
            continue
        if char == '"':
            in_string = True
        elif char == '{':
            depth += 1
        elif char == '}':
            depth -= 1
            if depth == 0:
                return text[brace_start + 1:index], text[index + 1:]
    raise SystemExit("unterminated phf_map! block in generated context")


def parse_context_pairs(path: pathlib.Path, marker: str) -> list[tuple[str, bytes]]:
    text = path.read_text(encoding="utf-8")
    entries_text, suffix = extract_marked_entries(text, marker)
    if not re.fullmatch(
        r'\s*,\s*&\s*\[\s*\]\s*,\s*phf_map\s*!\s*\{\s*\}\s*,\s*\)\s*\}\)\s*\}\s*',
        suffix,
    ):
        raise SystemExit(
            f"expected empty global/html hash metadata in Bazel-owned embedded assets block from {path}"
        )

    pairs = []
    for key, value in PAIR_RE.findall(entries_text):
        pairs.append((decode_rust_string(key), decode_rust_byte_string(value)))
    if not pairs:
        raise SystemExit(f"failed to parse embedded assets from {path}")
    return pairs


expected_input_pairs = parse_dist_pairs(pathlib.Path(sys.argv[1]))
generated_pairs = parse_generated_pairs(pathlib.Path(sys.argv[2]))
marker = f"RULES_TAURI_BAZEL_OWNED_EMBEDDED_ASSETS:{fnv1a64(pathlib.Path(sys.argv[2]).read_bytes()):016x}"
actual_pairs = parse_context_pairs(pathlib.Path(sys.argv[3]), marker)

generated_keys = [key for key, _ in generated_pairs]
expected_keys = [key for key, _ in expected_input_pairs]
actual_keys = [key for key, _ in actual_pairs]
if len(set(generated_keys)) != len(generated_keys):
    raise SystemExit(f"duplicate generated embedded asset keys detected: {generated_keys!r}")
if len(set(expected_keys)) != len(expected_keys):
    raise SystemExit(f"duplicate expected embedded asset keys detected: {expected_keys!r}")
if len(set(actual_keys)) != len(actual_keys):
    raise SystemExit(f"duplicate actual embedded asset keys detected: {actual_keys!r}")

if actual_pairs != generated_pairs:
    raise SystemExit(
        "codegen fixture embedded assets changed ordering or bytes relative to generated source\n"
        f"generated: {generated_pairs!r}\n"
        f"actual:    {actual_pairs!r}"
    )

expected = dict(expected_input_pairs)
actual = dict(actual_pairs)
if actual != expected:
    raise SystemExit(
        "codegen fixture embedded assets differ\n"
        f"expected: {expected!r}\n"
        f"actual:   {actual!r}"
    )
PY

echo "rules_rust tauri codegen fixture passed"
