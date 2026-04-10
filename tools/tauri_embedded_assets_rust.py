#!/usr/bin/env python3

import argparse
import json
import os
import subprocess
import tempfile
from pathlib import Path
from typing import Optional


def rust_string_literal(text: str) -> str:
    parts = ['"']
    for char in text:
        codepoint = ord(char)
        if char == "\\":
            parts.append(r"\\")
        elif char == '"':
            parts.append(r"\"")
        elif char == "\n":
            parts.append(r"\n")
        elif char == "\r":
            parts.append(r"\r")
        elif char == "\t":
            parts.append(r"\t")
        elif char == "\0":
            parts.append(r"\0")
        elif 0x20 <= codepoint <= 0x7E:
            parts.append(char)
        else:
            parts.append(f"\\u{{{codepoint:x}}}")
    parts.append('"')
    return "".join(parts)


def rust_byte_string_literal(data: bytes) -> str:
    parts = ['b"']
    for byte in data:
        if byte == 0x5C:
            parts.append(r"\\")
        elif byte == 0x22:
            parts.append(r"\"")
        elif byte == 0x0A:
            parts.append(r"\n")
        elif byte == 0x0D:
            parts.append(r"\r")
        elif byte == 0x09:
            parts.append(r"\t")
        elif byte == 0x00:
            parts.append(r"\0")
        elif 0x20 <= byte <= 0x7E:
            parts.append(chr(byte))
        else:
            parts.append(f"\\x{byte:02x}")
    parts.append('"')
    return "".join(parts)


def load_assets(
    root: Path, compressor: Optional[str] = None, quality: int = 2
) -> list[tuple[str, bytes]]:
    assets_by_key: dict[str, bytes] = {}
    for path in sorted(
        (path for path in root.rglob("*") if path.is_file()),
        key=lambda path: raw_asset_path(root, path),
    ):
        content = path.read_bytes()
        if compressor is not None:
            content = compress_bytes(path, content, compressor, quality)
        assets_by_key[asset_key(root, path)] = content
    return sorted(assets_by_key.items(), key=lambda item: item[0])


def load_transformed_assets(
    root: Path, transformer: str, compressor: Optional[str] = None, quality: int = 2
) -> tuple[list[tuple[str, bytes]], list[tuple[str, str]], list[tuple[str, list[tuple[str, str]]]]]:
    with tempfile.TemporaryDirectory(prefix="rules_tauri_transform_") as temp_dir:
        output_json = Path(temp_dir) / "transformed_assets.json"
        subprocess.run(
            [transformer, str(root), str(output_json)],
            check=True,
        )
        payload = json.loads(output_json.read_text(encoding="utf-8"))

    assets_by_key: dict[str, bytes] = {}
    for key, content in payload["assets"].items():
        asset_bytes = content.encode("utf-8")
        if compressor is not None:
            source = root / key.lstrip("/")
            asset_bytes = compress_bytes(source, asset_bytes, compressor, quality)
        assets_by_key[key] = asset_bytes

    global_hashes = [("script", value) for value in payload.get("global_script_hashes", [])]
    html_hashes = [
        (
            html_key,
            [("script", value) for value in values],
        )
        for html_key, values in sorted(payload.get("html_inline_hashes", {}).items())
    ]

    return (
        sorted(assets_by_key.items(), key=lambda item: item[0]),
        global_hashes,
        html_hashes,
    )


def asset_key(root: Path, path: Path) -> str:
    relative = path.relative_to(root)
    parts = [
        os.fsencode(part).decode("utf-8", "replace")
        for part in relative.parts
    ]
    return "/" + "/".join(parts)


def raw_asset_path(root: Path, path: Path) -> bytes:
    relative = path.relative_to(root)
    return b"/".join(os.fsencode(part) for part in relative.parts)


def compress_bytes(source: Path, content: bytes, compressor: str, quality: int) -> bytes:
    temp_dir = source.parent / ".rules_tauri_tmp_compress"
    temp_dir.mkdir(parents=True, exist_ok=True)
    temp_input = temp_dir / (source.name + ".input")
    temp_output = temp_dir / (source.name + ".br")
    temp_input.write_bytes(content)
    try:
        subprocess.run(
            [compressor, str(temp_input), str(temp_output), str(quality)],
            check=True,
        )
        return temp_output.read_bytes()
    finally:
        temp_input.unlink(missing_ok=True)
        temp_output.unlink(missing_ok=True)
        try:
            temp_dir.rmdir()
        except OSError:
            pass


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("input_dir")
    parser.add_argument("output_file")
    parser.add_argument("--compressor")
    parser.add_argument("--compression-quality", type=int, default=2)
    parser.add_argument("--transformer")
    args = parser.parse_args()

    root = Path(args.input_dir)
    if args.transformer:
        assets, global_hashes, html_hashes = load_transformed_assets(
            root,
            args.transformer,
            args.compressor,
            args.compression_quality,
        )
    else:
        assets = load_assets(root, args.compressor, args.compression_quality)
        global_hashes = []
        html_hashes = []

    output = Path(args.output_file)
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("w", encoding="utf-8", newline="\n") as stream:
        stream.write("// @generated by tools/tauri_embedded_assets_rust.py\n")
        stream.write("// DO NOT EDIT.\n\n")
        stream.write("pub const EMBEDDED_ASSETS: &[(&str, &[u8])] = &[\n")
        for key, content in assets:
            stream.write(
                f"    ({rust_string_literal(key)}, {rust_byte_string_literal(content)}),\n"
            )
        stream.write("];\n")
        stream.write("\n")
        stream.write('pub const GLOBAL_CSP_HASHES: &[(&str, &str)] = &[\n')
        for kind, value in global_hashes:
            stream.write(
                f"    ({rust_string_literal(kind)}, {rust_string_literal(value)}),\n"
            )
        stream.write("];\n")
        stream.write("\n")
        stream.write('pub const HTML_CSP_HASHES: &[(&str, &[(&str, &str)])] = &[\n')
        for html_key, hashes in html_hashes:
            stream.write(f"    ({rust_string_literal(html_key)}, &[\n")
            for kind, value in hashes:
                stream.write(
                    f"        ({rust_string_literal(kind)}, {rust_string_literal(value)}),\n"
                )
            stream.write("    ]),\n")
        stream.write("];\n")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
