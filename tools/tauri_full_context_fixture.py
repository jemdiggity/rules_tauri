#!/usr/bin/env python3
import argparse
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", required=True)
    parser.add_argument("--embedded-assets-rust", required=True)
    parser.add_argument("--runtime-authority-rust", required=True)
    parser.add_argument("--product-name", required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--identifier", required=True)
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


def main() -> None:
    args = parse_args()
    embedded_assets = Path(args.embedded_assets_rust).read_text(encoding="utf-8").strip()
    runtime_authority = Path(args.runtime_authority_rust).read_text(encoding="utf-8").strip()
    Path(args.out).write_text(
        (
            "// placeholder full fixture context\n"
            f"const _: &str = {rust_string(args.product_name)};\n"
            f"const _: &str = {rust_string(args.version)};\n"
            f"const _: &str = {rust_string(args.identifier)};\n"
            f"const _: &str = {rust_string(embedded_assets)};\n"
            f"const _: &str = {rust_string(runtime_authority)};\n"
        ),
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
