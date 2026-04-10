#!/usr/bin/env python3

import json
import os
from pathlib import Path


def walk_files(root: Path):
    for entry in os.scandir(root):
        path = Path(entry.path)
        if entry.is_dir(follow_symlinks=True):
            yield from walk_files(path)
        elif entry.is_file(follow_symlinks=True):
            yield path


def main() -> None:
    root = Path(__file__).resolve().parent / "assets"
    ordered = ["/" + path.relative_to(root).as_posix() for path in walk_files(root)]
    print(json.dumps(ordered, indent=2))


if __name__ == "__main__":
    main()
