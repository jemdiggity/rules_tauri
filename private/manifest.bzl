"""Manifest helpers for rules_tauri internals."""

def manifest_entry(source, destination, kind):
    return {
        "source": source,
        "destination": destination,
        "kind": kind,
    }

def encode_manifest(entries, metadata):
    sorted_entries = sorted(entries, key = lambda entry: entry["destination"])
    return json.encode({
        "metadata": metadata,
        "entries": sorted_entries,
    })
