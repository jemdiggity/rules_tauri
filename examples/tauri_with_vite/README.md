# tauri_with_vite

This example vendors a real `create tauri-app` Tauri 2 + Vue + Vite application and packages it with `rules_tauri`.

The example is intentionally split in two:

- `app/` contains the vendored application source so the example matches a real generated project.
- `src/` contains checked-in packaging inputs that are not generated during the example build: icon and Tauri config.

The example now uses the high-level `tauri_application(...)` macro in `app/src-tauri/BUILD.bazel`. Bazel owns frontend normalization, embedded-assets generation, release context generation, release-source rewriting, Rust release binary wiring, and unsigned macOS app assembly. The example still keeps `build.rs` for dev-oriented Cargo/Tauri CLI flows.

For release assembly parity with normal Tauri builds, the frontend assets are embedded into the Tauri binary before `rules_tauri` bundles the app. They are not copied into `Contents/Resources/frontend/...` in the final `.app`. In this example path, `tauri_application(...)` owns the frontend normalization and embedded-assets seam instead of relying on the local crate `build.rs` or a separately precomputed target in the release graph.

Build with:

```sh
bazel build //examples/tauri_with_vite:app_arm64 //examples/tauri_with_vite:app_x86_64
```

The vendored source started from the current upstream generator's Vue template and was then adapted to use pnpm as the package-manager source of truth for Bazel:

```sh
pnpm create tauri-app@latest --template vue --manager pnpm --yes tauri-with-vite
cd tauri-with-vite
```
