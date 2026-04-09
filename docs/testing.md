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

The current smoke path is:

```sh
sh ./test/validate_examples.sh
```

## Repository contract

`examples/` are part of the public contract and should stay green.
