#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$repo_root"

bazel build --action_env=PATH \
  //examples/minimal_macos:bundle_inputs_arm64 \
  //examples/minimal_macos:app_arm64 \
  //examples/minimal_macos:bundle_inputs_x86_64 \
  //examples/minimal_macos:app_x86_64 \
  //examples/minimal_macos/src-tauri:app_arm64_embedded_assets_rust \
  //examples/tauri_with_vite/app/src-tauri:tauri_with_vite_lib \
  //examples/tauri_with_vite:bundle_inputs_arm64 \
  //examples/tauri_with_vite:app_arm64 \
  //examples/tauri_with_vite:bundle_inputs_x86_64 \
  //examples/tauri_with_vite:app_x86_64

arm64_app="$repo_root/bazel-bin/examples/minimal_macos/src-tauri/app_arm64.app"
x86_app="$repo_root/bazel-bin/examples/minimal_macos/src-tauri/app_x86_64.app"
vite_arm64_app="$repo_root/bazel-bin/examples/tauri_with_vite/app/src-tauri/app_arm64.app"
vite_x86_app="$repo_root/bazel-bin/examples/tauri_with_vite/app/src-tauri/app_x86_64.app"
minimal_embedded_assets="$repo_root/bazel-bin/examples/minimal_macos/src-tauri/app_arm64_embedded_assets_rust.rs"

grep -q '(\"/index.html\", ' "$minimal_embedded_assets"

test -f "$arm64_app/Contents/Info.plist"
test -f "$arm64_app/Contents/MacOS/minimal-app"
test -f "$arm64_app/Contents/MacOS/helper-sidecar"
test -f "$arm64_app/Contents/Resources/resources/examples/minimal_macos/src/resources/example.txt"
test -f "$arm64_app/Contents/Resources/legal/license.txt"
test -f "$arm64_app/Contents/Resources/icon.icns"
test -f "$arm64_app/Contents/Frameworks/Fake"
test -f "$arm64_app/Contents/Helpers/extra.conf"
file "$arm64_app/Contents/MacOS/minimal-app" | grep -q "Mach-O 64-bit executable arm64"
strings "$arm64_app/Contents/MacOS/minimal-app" | grep -q "/index.html"
strings "$arm64_app/Contents/MacOS/minimal-app" | grep -q "Hello, "

test -f "$x86_app/Contents/Info.plist"
test -f "$x86_app/Contents/MacOS/minimal-app"
test -f "$x86_app/Contents/MacOS/helper-sidecar"
file "$x86_app/Contents/MacOS/minimal-app" | grep -q "Mach-O 64-bit executable x86_64"
strings "$x86_app/Contents/MacOS/minimal-app" | grep -q "/index.html"

test -f "$vite_arm64_app/Contents/Info.plist"
test -f "$vite_arm64_app/Contents/MacOS/tauri-with-vite"
test -f "$vite_arm64_app/Contents/Resources/icon.icns"
test ! -e "$vite_arm64_app/Contents/Resources/frontend"
file "$vite_arm64_app/Contents/MacOS/tauri-with-vite" | grep -q "Mach-O 64-bit executable arm64"
strings "$vite_arm64_app/Contents/MacOS/tauri-with-vite" | grep -q "/assets/index-"
strings "$vite_arm64_app/Contents/MacOS/tauri-with-vite" | grep -q "/vite.svg"

test -f "$vite_x86_app/Contents/Info.plist"
test -f "$vite_x86_app/Contents/MacOS/tauri-with-vite"
file "$vite_x86_app/Contents/MacOS/tauri-with-vite" | grep -q "Mach-O 64-bit executable x86_64"
strings "$vite_x86_app/Contents/MacOS/tauri-with-vite" | grep -q "/assets/index-"

aquery_output=$(mktemp)
trap 'rm -f "$aquery_output"' EXIT
bazel aquery //examples/tauri_with_vite/app/src-tauri:tauri_with_vite_lib >"$aquery_output"
if grep -Eq "examples/tauri_with_vite/app/src-tauri/build\\.rs|examples/tauri_with_vite/app/src-tauri:build_script|RULES_TAURI_BAZEL_(FULL_CONTEXT|ACL_OUT_DIR|UPSTREAM_OUT_DIR)" "$aquery_output"; then
  echo "expected Bazel release example graph to avoid Cargo build-script wiring" >&2
  exit 1
fi

echo "rules_tauri example validation passed"
