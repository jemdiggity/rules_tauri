#!/usr/bin/env python3

import argparse
import json
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("input_dir")
    parser.add_argument("output_file")
    args = parser.parse_args()

    root = Path(args.input_dir)
    asset_keys = sorted(
        "/" + path.relative_to(root).as_posix()
        for path in root.rglob("*")
        if path.is_file()
    )

    output = Path(args.output_file)
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("w", encoding="utf-8") as stream:
        json.dump(asset_keys, stream, indent=2)
        stream.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
