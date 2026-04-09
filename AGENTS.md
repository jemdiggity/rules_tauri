# AGENTS.md

## Scope

`rules_tauri` owns Tauri-specific release assembly only. It stops at an unsigned macOS `.app`.

Do not expand the scope to code signing, DMG creation, notarization, or dev workflow support unless the change is explicitly intended to broaden the public contract.

## Public API

Public API lives only in:

- `//tauri:defs.bzl`
- `//tauri:providers.bzl`

Everything under `//private` is implementation detail and may be refactored freely.

## Stability

- Preserve Bzlmod compatibility.
- Preserve Bazel Central Registry publishability.
- Prefer additive API changes over breaking ones.

## Testing

- Keep `examples/` green.
- Add or update tests for bundle layout changes.
- Verify rule outputs are deterministic.
