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


def main() -> None:
    args = parse_args()
    embedded_assets = Path(args.embedded_assets_rust).read_text(encoding="utf-8").strip()
    runtime_authority = Path(args.runtime_authority_rust).read_text(encoding="utf-8").strip()
    Path(args.out).write_text(
        (
            "// placeholder full fixture context\n"
            f"const _: &str = {args.product_name!r};\n"
            f"const _: &str = {args.version!r};\n"
            f"const _: &str = {args.identifier!r};\n"
            f"const _: &str = {embedded_assets!r};\n"
            f"const _: &str = {runtime_authority!r};\n"
        ),
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
