#!/usr/bin/env python3

import argparse
import json
import plistlib
from pathlib import Path


def load_tauri_config(path):
    if not path:
        return {}
    return json.loads(Path(path).read_text())


def get_nested(mapping, *keys):
    current = mapping
    for key in keys:
        if not isinstance(current, dict):
            return None
        current = current.get(key)
    return current


def merge_dicts(base, override):
    result = dict(base)
    for key, value in override.items():
        if isinstance(value, dict) and isinstance(result.get(key), dict):
            result[key] = merge_dicts(result[key], value)
        else:
            result[key] = value
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True)
    parser.add_argument("--bundle-id", required=True)
    parser.add_argument("--product-name", required=True)
    parser.add_argument("--version")
    parser.add_argument("--version-file")
    parser.add_argument("--main-binary-name", required=True)
    parser.add_argument("--tauri-config")
    parser.add_argument("--plist-fragment", action="append", default=[])
    parser.add_argument("--icon-name")
    args = parser.parse_args()

    if bool(args.version) == bool(args.version_file):
        raise SystemExit("exactly one of --version or --version-file must be provided")

    version = args.version
    if args.version_file:
        version = Path(args.version_file).read_text().strip()

    config = load_tauri_config(args.tauri_config)
    bundle_config = config.get("bundle", {})
    macos_config = bundle_config.get("macOS", bundle_config.get("macos", {}))

    bundle_name = macos_config.get("bundleName") or args.product_name
    bundle_version = macos_config.get("bundleVersion") or version
    minimum_system_version = macos_config.get("minimumSystemVersion") or "10.13"

    plist = {
        "CFBundleDevelopmentRegion": "English",
        "CFBundleDisplayName": args.product_name,
        "CFBundleExecutable": args.main_binary_name,
        "CFBundleIdentifier": args.bundle_id,
        "CFBundleInfoDictionaryVersion": "6.0",
        "CFBundleName": bundle_name,
        "CFBundlePackageType": "APPL",
        "CFBundleShortVersionString": version,
        "CFBundleVersion": bundle_version,
        "CSResourcesFileMapped": True,
        "LSRequiresCarbon": True,
        "NSHighResolutionCapable": True,
    }

    plist["LSMinimumSystemVersion"] = minimum_system_version
    if args.icon_name:
        plist["CFBundleIconFile"] = args.icon_name

    for fragment_path in args.plist_fragment:
        fragment = plistlib.loads(Path(fragment_path).read_bytes())
        if isinstance(fragment, dict):
            plist = merge_dicts(plist, fragment)

    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(plistlib.dumps(plist, fmt=plistlib.FMT_XML, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
