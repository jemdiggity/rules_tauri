"""Path normalization helpers for rules_tauri internals."""

def _normalize_parts(parts, absolute_behavior):
    normalized = []
    for part in parts:
        if part in ["", "."]:
            continue
        if part == "..":
            normalized.append("_up_")
            continue
        normalized.append(part)

    if absolute_behavior and normalized:
        return [absolute_behavior] + normalized
    return normalized

def normalize_resource_relpath(path):
    """Normalizes a source-relative path using Tauri-like synthetic root markers."""
    absolute_behavior = None
    if path.startswith("/"):
        absolute_behavior = "_root_"
    return "/".join(_normalize_parts(path.split("/"), absolute_behavior))

def normalize_bundle_relative_path(path):
    """Normalizes a caller-supplied destination path under bundle-relative semantics."""
    return "/".join(_normalize_parts(path.split("/"), None))

def strip_target_triple_suffix(path, target_triple):
    filename = path.split("/")[-1]
    suffix = "-%s" % target_triple
    if filename.endswith(suffix):
        return filename[:-len(suffix)]
    return filename
