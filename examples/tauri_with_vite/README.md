# tauri_with_vite

This example vendors a real `create tauri-app` Tauri 2 + Vue + Vite application and packages it with `rules_tauri`.

The example is intentionally split in two:

- `app/` contains the vendored application source so the example matches a real generated project.
- `src/` contains checked-in packaging inputs that are not generated during the example build: icon and Tauri config.

The example-specific Bazel glue builds the frontend assets and the Tauri Rust binary from `app/`, then passes those generated outputs through the public `rules_tauri` interface. `rules_tauri` itself still only assembles the unsigned macOS `.app`.

For release assembly parity with normal Tauri builds, the frontend assets are expected to be embedded into the Tauri binary before `rules_tauri` bundles the app. They are not copied into `Contents/Resources/frontend/...` in the final `.app`.

Build with:

```sh
bazel build //examples/tauri_with_vite:app_arm64 //examples/tauri_with_vite:app_x86_64
```

The vendored source started from the current upstream generator's Vue template and was then adapted to use pnpm as the package-manager source of truth for Bazel:

```sh
pnpm create tauri-app@latest --template vue --manager pnpm --yes tauri-with-vite
cd tauri-with-vite
```
