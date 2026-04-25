# Testing

## Unit coverage

The implementation should eventually have focused tests for:

- plist generation and merge order
- resource path normalization
- sidecar staging and target-triple handling
- framework staging
- app bundle layout generation

## End-to-end coverage

Examples should verify:

- unsigned `.app` assembly for `aarch64-apple-darwin`
- unsigned `.app` assembly for `x86_64-apple-darwin`
- real Mach-O app binaries can be packaged for at least one realistic Tauri example
- release bundle layout stays aligned with `cargo tauri build` for the checked parity dimensions
- deterministic manifests across repeated builds
- Bazel-owned embedded asset generation stays aligned with upstream Tauri embedding semantics under `rules_rust`

The current smoke path is:

```sh
sh ./test/validate_examples.sh
```

The focused `rules_rust`/Tauri codegen probe is:

```sh
./test/validate_rules_rust_codegen_fixture.sh
```

The bundle collision regression is:

```sh
./test/validate_bundle_destination_collisions.sh
```

The embedded-assets seam comparisons are:

```sh
./test/compare_embedded_assets_order.sh
./test/compare_embedded_assets_rust.sh
```

## Repository contract

`examples/` are part of the public contract and should stay green.
