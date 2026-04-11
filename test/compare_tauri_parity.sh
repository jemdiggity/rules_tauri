#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
. "$repo_root/test/oracle_build_common.sh"
app_root="$repo_root/examples/tauri_with_vite/app"
src_tauri_dir="$app_root/src-tauri"
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
oracle_app="$tmpdir/app"
oracle_src_tauri="$oracle_app/src-tauri"

cp -R "$app_root" "$oracle_app"
oracle_build_prepare_src_tauri "$oracle_src_tauri"

cd "$oracle_app"
pnpm install --frozen-lockfile
pnpm build

cd "$oracle_app"
pnpm exec tauri build --bundles app

upstream_app="$oracle_src_tauri/target/release/bundle/macos/tauri-with-vite.app"
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
