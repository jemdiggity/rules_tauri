# rules_tauri Design

## Goal

`rules_tauri` defines a Bazel-native assembly layer for Tauri release builds.

The v1 boundary is deliberately narrow:

- consume already-built frontend assets
- consume already-built Rust application binaries
- consume already-built sidecars
- interpret Tauri packaging metadata
- emit a deterministic unsigned macOS `.app`

Everything after `.app` creation belongs to non-Tauri release rules.

## Boundary

The intended split is:

1. other Bazel rules build `frontend_dist`, `main_binary`, `sidecars`, and supporting files
2. `rules_tauri` normalizes those inputs and assembles an unsigned `.app`
3. Apple/release rules sign, package, notarize, staple, and publish

This keeps Tauri-specific logic isolated from generic macOS release machinery.

## Upstream Contract

The design is grounded in the current upstream Tauri implementation:

- `tauri-build` treats `build.frontendDist` as the release asset input
- `tauri-utils` defines resource path normalization and config semantics
- `tauri-bundler` assembles `.app` contents, including icons, frameworks, resources, sidecars, app binaries, and `macOS.files`
- `Info.plist` is synthesized first and then merged with user plist data

Key behaviors to preserve:

- target-triple validation for sidecars
- deterministic resource path normalization
- stripping target suffixes from staged sidecar names
- deterministic plist generation and merge ordering
- macOS custom file injection under `Contents`
- framework copying as part of app assembly

## Public Rules

V1 exposes exactly two public rules:

- `tauri_bundle_inputs`
- `tauri_macos_app`

The consumer-facing load path is:

```starlark
load("@rules_tauri//tauri:defs.bzl", "tauri_bundle_inputs", "tauri_macos_app")
```

## Non-Goals

- `tauri dev`
- Bun/Vite dev workflows
- Rust compilation rules
- JS bundler rules
- signing
- DMG creation
- notarization
- Windows and Linux packaging
