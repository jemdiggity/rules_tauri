#!/usr/bin/env python3

import json
from pathlib import Path


def main() -> None:
    root = Path(__file__).resolve().parent / "assets"
    ordered = sorted(
        "/" + path.relative_to(root).as_posix()
        for path in root.rglob("*")
        if path.is_file()
    )
    print(json.dumps(ordered, indent=2))


if __name__ == "__main__":
    main()
