#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
app_root="$repo_root/examples/tauri_with_vite/app"
src_tauri_dir="$app_root/src-tauri"

cd "$app_root"
bun install
bun run build

cd "$app_root"
bun run tauri build --bundles app

upstream_app="$src_tauri_dir/target/release/bundle/macos/tauri-with-vite.app"
cd "$repo_root"
bazel build --action_env=PATH //examples/tauri_with_vite:app_arm64 >/dev/null
bazel_app="$repo_root/bazel-bin/examples/tauri_with_vite/app_arm64.app"

test -d "$upstream_app"
test -d "$bazel_app"

upstream_exe="$upstream_app/Contents/MacOS/tauri-with-vite"
bazel_exe=$(find -L "$bazel_app/Contents/MacOS" -maxdepth 1 -type f | head -n 1)

test -f "$upstream_exe"
test -f "$bazel_exe"
test ! -e "$bazel_app/Contents/Resources/frontend"
test "$(basename "$upstream_exe")" = "$(basename "$bazel_exe")"
strings "$upstream_exe" | grep -q "/assets/index-"
strings "$upstream_exe" | grep -q "/vite.svg"
strings "$bazel_exe" | grep -q "/assets/index-"
strings "$bazel_exe" | grep -q "/vite.svg"

echo "tauri parity comparison passed"
