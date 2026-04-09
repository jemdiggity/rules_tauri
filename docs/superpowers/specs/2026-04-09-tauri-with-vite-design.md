# Vendored Tauri Vue/Vite Example Design

## Goal

Replace the placeholder `examples/tauri_with_vite` workspace with a real, self-contained example based on the current `create tauri-app` Vue/Vite template while preserving `rules_tauri`'s narrow responsibility: assemble an unsigned macOS `.app` from already-produced inputs.

## Constraints

- Keep the repository contract packaging-focused. `rules_tauri` must still stop at an unsigned `.app`.
- Keep the example self-contained in git. No `bun create tauri-app` step may be required for tests.
- Keep `examples/` green and extend smoke coverage to include the new example.
- Avoid introducing signing, notarization, DMG, or dev-workflow behavior into the public contract.

## Proposed Structure

`examples/tauri_with_vite` will contain:

- vendored source files closely matching a generated Tauri 2 + Vue + Vite app
- prebuilt frontend assets under an example-owned fixture directory
- prebuilt per-arch macOS binaries under an example-owned fixture directory
- Bazel targets that feed those built artifacts into `tauri_bundle_inputs` and `tauri_macos_app`

The example sources exist to make the example understandable and regenerable. Bazel consumes the checked-in built outputs, not a live Bun or Cargo build step. That keeps the example aligned with the repo boundary while still representing a real app layout.

## Asset Production

The generated app shape will be created from the current upstream template in a temporary directory, then copied into the repo with small adjustments only where needed for deterministic packaging fixtures.

Checked-in fixtures will include:

- `frontend_dist/` generated from the Vue/Vite build output
- `bin/tauri-with-vite-aarch64-apple-darwin`
- `bin/tauri-with-vite-x86_64-apple-darwin`
- app icon and Tauri config sourced from the vendored app

If the generated project does not produce both macOS architectures from this machine with a trivial command, the example may initially ship one real host-arch binary plus one documented placeholder only if validation remains explicit about that limitation. The preferred outcome is real binaries for both architectures.

## Testing

The example validation script will be extended to:

- build `//examples/tauri_with_vite:app_arm64` and `//examples/tauri_with_vite:app_x86_64`
- assert the expected bundle files exist
- verify the bundled executable is a Mach-O binary, not a shell script
- keep the validation layout deterministic

## Documentation

The example README will state:

- it is a vendored `create tauri-app` Vue/Vite example
- Bazel packages checked-in build outputs to preserve the repository boundary
- how the vendored sources and fixtures were produced or refreshed

## Risks And Decisions

- Upstream template churn: acceptable, because the example is vendored and can be refreshed intentionally.
- Cross-arch binary generation on one machine: this is the main implementation risk and should be resolved pragmatically during implementation.
- Example size growth: acceptable if limited to one realistic example and its packaging fixtures.
