#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$repo_root"

bazel build --action_env=PATH \
  //examples/minimal_macos:bundle_inputs_arm64 \
  //examples/minimal_macos:app_arm64 \
  //examples/minimal_macos:bundle_inputs_x86_64 \
  //examples/minimal_macos:app_x86_64 \
  //examples/tauri_with_vite/app/src-tauri:build_script \
  //examples/tauri_with_vite:bundle_inputs_arm64 \
  //examples/tauri_with_vite:app_arm64 \
  //examples/tauri_with_vite:bundle_inputs_x86_64 \
  //examples/tauri_with_vite:app_x86_64

arm64_app="$repo_root/bazel-bin/examples/minimal_macos/app_arm64.app"
x86_app="$repo_root/bazel-bin/examples/minimal_macos/app_x86_64.app"
vite_arm64_app="$repo_root/bazel-bin/examples/tauri_with_vite/app_arm64.app"
vite_x86_app="$repo_root/bazel-bin/examples/tauri_with_vite/app_x86_64.app"
build_flags="$repo_root/bazel-bin/examples/tauri_with_vite/app/src-tauri/build_script.flags"
build_env="$repo_root/bazel-bin/examples/tauri_with_vite/app/src-tauri/build_script.env"
build_depenv="$repo_root/bazel-bin/examples/tauri_with_vite/app/src-tauri/build_script.depenv"

test -f "$arm64_app/Contents/Info.plist"
test -f "$arm64_app/Contents/MacOS/minimal-app"
test -f "$arm64_app/Contents/MacOS/helper-sidecar"
test -f "$arm64_app/Contents/Resources/resources/examples/minimal_macos/src/resources/example.txt"
test -f "$arm64_app/Contents/Resources/legal/license.txt"
test -f "$arm64_app/Contents/Resources/AppIcon.icns"
test -f "$arm64_app/Contents/Frameworks/Fake"
test -f "$arm64_app/Contents/Helpers/extra.conf"

test -f "$x86_app/Contents/Info.plist"
test -f "$x86_app/Contents/MacOS/minimal-app"
test -f "$x86_app/Contents/MacOS/helper-sidecar"

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

test -f "$build_flags"
test -f "$build_env"
test -f "$build_depenv"
grep -q "TAURI_ANDROID_PACKAGE_NAME_APP_NAME=tauri_with_vite" "$build_env"
grep -q "TAURI_ANDROID_PACKAGE_NAME_PREFIX=com_jeremyhale" "$build_env"
grep -q "TAURI_ENV_TARGET_TRIPLE=aarch64-apple-darwin" "$build_env"
grep -q -- "--cfg=desktop" "$build_flags"
grep -q -- "--cfg=dev" "$build_flags"
grep -q "build_script.out_dir/app-manifest/__app__-permission-files" "$build_depenv"
aquery_output=$(mktemp)
trap 'rm -f "$aquery_output"' EXIT
bazel aquery //examples/tauri_with_vite/app/src-tauri:build_script >"$aquery_output"
grep -q "RULES_TAURI_BAZEL_FULL_CONTEXT" "$aquery_output"
grep -q "RULES_TAURI_BAZEL_ACL_OUT_DIR" "$aquery_output"
if grep -Eq "upstream_build_script\\.out_dir|RULES_TAURI_BAZEL_UPSTREAM_OUT_DIR" "$aquery_output"; then
  echo "expected real example build graph to be helper-free, but upstream helper wiring is still present" >&2
  exit 1
fi

echo "rules_tauri example validation passed"
