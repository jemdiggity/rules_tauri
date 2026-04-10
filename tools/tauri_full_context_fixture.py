#!/usr/bin/env python3
import argparse
import re
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", required=True)
    parser.add_argument("--embedded-assets-rust", required=True)
    parser.add_argument("--upstream-context-rust", required=True)
    return parser.parse_args()


def rust_string(value: str) -> str:
    parts = ['"']
    for char in value:
        codepoint = ord(char)
        if char == '"':
            parts.append('\\"')
        elif char == '\\':
            parts.append('\\\\')
        elif char == '\n':
            parts.append('\\n')
        elif char == '\r':
            parts.append('\\r')
        elif char == '\t':
            parts.append('\\t')
        elif 0x20 <= codepoint <= 0x7E:
            parts.append(char)
        else:
            parts.append(f'\\u{{{codepoint:x}}}')
    parts.append('"')
    return "".join(parts)


def decode_rust_string(token: str) -> str:
    if not (token.startswith('"') and token.endswith('"')):
        raise ValueError(f"expected Rust string literal, got {token!r}")

    index = 1
    chars: list[str] = []
    while index < len(token) - 1:
        char = token[index]
        if char != "\\":
            chars.append(char)
            index += 1
            continue

        index += 1
        escape = token[index]
        if escape == "\\":
            chars.append("\\")
            index += 1
        elif escape == '"':
            chars.append('"')
            index += 1
        elif escape == "n":
            chars.append("\n")
            index += 1
        elif escape == "r":
            chars.append("\r")
            index += 1
        elif escape == "t":
            chars.append("\t")
            index += 1
        elif escape == "0":
            chars.append("\0")
            index += 1
        elif escape == "u":
            if token[index + 1] != "{":
                raise ValueError(f"unsupported Rust unicode escape in {token!r}")
            end = token.index("}", index + 2)
            chars.append(chr(int(token[index + 2:end], 16)))
            index = end + 1
        else:
            raise ValueError(f"unsupported Rust string escape \\{escape}")
    return "".join(chars)


def fnv1a64(data: bytes) -> int:
    value = 0xCBF29CE484222325
    for byte in data:
        value ^= byte
        value = (value * 0x100000001B3) & 0xFFFFFFFFFFFFFFFF
    return value


def extract_const_array(text: str, const_name: str) -> str:
    marker = f"pub const {const_name}"
    start = text.find(marker)
    if start < 0:
        raise ValueError(f"failed to find {const_name}")

    equals_index = text.find("=", start)
    if equals_index < 0:
        raise ValueError(f"failed to locate assignment for {const_name}")

    array_start = text.find("&[", equals_index)
    if array_start < 0:
        raise ValueError(f"failed to locate array start for {const_name}")

    depth = 0
    in_string = False
    escaped = False
    for index in range(array_start + 1, len(text)):
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
        elif char == "[":
            depth += 1
        elif char == "]":
            depth -= 1
            if depth == 0:
                return text[array_start + 2:index]

    raise ValueError(f"unterminated array literal for {const_name}")


EMBEDDED_ASSET_RE = re.compile(
    r'\(\s*("(?:(?:\\.)|[^"])*")\s*,\s*(b"(?:(?:\\.)|[^"])*")\s*\),?',
    re.S,
)
HASH_RE = re.compile(
    r'\(\s*("(?:(?:\\.)|[^"])*")\s*,\s*("(?:(?:\\.)|[^"])*")\s*\),?',
    re.S,
)
HTML_HASH_RE = re.compile(
    r'\(\s*("(?:(?:\\.)|[^"])*")\s*,\s*&\[\s*(.*?)\s*\]\s*\),?',
    re.S,
)


def render_csp_hash(kind_token: str, value_token: str) -> str:
    kind = decode_rust_string(kind_token)
    if kind == "script":
        return f"::tauri::utils::assets::CspHash::Script({value_token})"
    if kind == "style":
        return f"::tauri::utils::assets::CspHash::Style({value_token})"
    raise ValueError(f"unsupported CSP hash kind {kind!r}")


def render_embedded_assets_expr(embedded_assets_source: str, embedded_assets_bytes: bytes) -> str:
    assets_body = extract_const_array(embedded_assets_source, "EMBEDDED_ASSETS")
    global_hashes_body = extract_const_array(embedded_assets_source, "GLOBAL_CSP_HASHES")
    html_hashes_body = extract_const_array(embedded_assets_source, "HTML_CSP_HASHES")

    asset_entries = EMBEDDED_ASSET_RE.findall(assets_body)
    if not asset_entries:
        raise ValueError("failed to parse EMBEDDED_ASSETS entries")

    global_hash_entries = HASH_RE.findall(global_hashes_body)

    html_hash_entries = []
    for html_key, hashes_body in HTML_HASH_RE.findall(html_hashes_body):
        hashes = HASH_RE.findall(hashes_body)
        html_hash_entries.append((html_key, hashes))

    marker = f"RULES_TAURI_BAZEL_OWNED_EMBEDDED_ASSETS:{fnv1a64(embedded_assets_bytes):016x}"

    lines = [
        "{",
        "    #[allow(unused_imports)]",
        "    use ::tauri::utils::assets::{CspHash, EmbeddedAssets, phf, phf::phf_map};",
        f"    const _: &str = {rust_string(marker)};",
        "    EmbeddedAssets::new(",
        "        phf_map! {",
    ]
    for key, value in asset_entries:
        lines.append(f"            {key} => {value},")
    lines.extend(
        [
            "        },",
            "        &[",
        ]
    )
    for kind, value in global_hash_entries:
        lines.append(f"            {render_csp_hash(kind, value)},")
    lines.extend(
        [
            "        ],",
            "        phf_map! {",
        ]
    )
    for html_key, hashes in html_hash_entries:
        lines.append(f"            {html_key} => &[")
        for kind, value in hashes:
            lines.append(f"                {render_csp_hash(kind, value)},")
        lines.append("            ],")
    lines.extend(
        [
            "        },",
            "    )",
            "}",
        ]
    )
    return "\n".join(lines)


def find_matching_delimiter(text: str, start_index: int, open_char: str, close_char: str) -> int:
    depth = 0
    in_string = False
    escaped = False

    for index in range(start_index, len(text)):
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
            continue

        if char == open_char:
            depth += 1
        elif char == close_char:
            depth -= 1
            if depth == 0:
                return index

    raise ValueError(f"unterminated {open_char}{close_char} expression")


def patch_inner_assets_expr(upstream_context: str, embedded_assets_expr: str) -> str:
    matches = list(re.finditer(r"\binner\s*\(", upstream_context))
    if not matches:
        raise ValueError("failed to locate final inner(...) call in upstream context")

    match = matches[-1]
    open_paren_index = upstream_context.find("(", match.start())
    close_paren_index = find_matching_delimiter(upstream_context, open_paren_index, "(", ")")
    return (
        upstream_context[: open_paren_index + 1]
        + embedded_assets_expr
        + upstream_context[close_paren_index:]
    )


def main() -> None:
    args = parse_args()
    embedded_assets_path = Path(args.embedded_assets_rust)
    embedded_assets_bytes = embedded_assets_path.read_bytes()
    embedded_assets = embedded_assets_bytes.decode("utf-8")
    upstream_context = Path(args.upstream_context_rust).read_text(encoding="utf-8")
    Path(args.out).write_text(
        patch_inner_assets_expr(
            upstream_context=upstream_context,
            embedded_assets_expr=render_embedded_assets_expr(embedded_assets, embedded_assets_bytes),
        ),
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
