#!/usr/bin/env python3

import argparse
import json
import shutil
from pathlib import Path


def ensure_parent(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--spec", required=True)
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--output-manifest", required=True)
    args = parser.parse_args()

    spec = json.loads(Path(args.spec).read_text())
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    manifest_entries = []
    seen_destinations = {}
    for entry in spec["entries"]:
        source = Path(entry["source"])
        destination = output_dir / entry["destination"]
        destination_key = entry["destination"]
        if destination_key in seen_destinations:
            previous = seen_destinations[destination_key]
            raise SystemExit(
                "duplicate manifest destination "
                f"{destination_key!r} from {entry['source']} and {previous['source']}"
            )
        seen_destinations[destination_key] = entry
        ensure_parent(destination)
        shutil.copy2(source, destination)
        manifest_entries.append(
            {
                "kind": entry["kind"],
                "source": str(source),
                "destination": entry["destination"],
            }
        )

    output_manifest = {
        "metadata": spec["metadata"],
        "entries": sorted(manifest_entries, key=lambda item: item["destination"]),
    }
    Path(args.output_manifest).write_text(json.dumps(output_manifest, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
