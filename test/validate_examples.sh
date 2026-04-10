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
  //examples/tauri_with_vite/app/src-tauri:upstream_build_script \
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
upstream_flags="$repo_root/bazel-bin/examples/tauri_with_vite/app/src-tauri/upstream_build_script.flags"
upstream_env="$repo_root/bazel-bin/examples/tauri_with_vite/app/src-tauri/upstream_build_script.env"
upstream_depenv="$repo_root/bazel-bin/examples/tauri_with_vite/app/src-tauri/upstream_build_script.depenv"

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
test -f "$upstream_flags"
test -f "$upstream_env"
test -f "$upstream_depenv"
cmp -s "$build_flags" "$upstream_flags"
cmp -s "$build_env" "$upstream_env"
python3 - "$build_depenv" "$upstream_depenv" <<'PY'
import pathlib
import re
import sys

def normalize(text: str) -> str:
    return re.sub(r"build_script\.out_dir", "OUT_DIR", re.sub(r"upstream_build_script\.out_dir", "OUT_DIR", text))

build = normalize(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
upstream = normalize(pathlib.Path(sys.argv[2]).read_text(encoding="utf-8"))
if build != upstream:
    raise SystemExit(f"build script depenv mismatch\nexpected:\n{upstream}\nactual:\n{build}")
PY

echo "rules_tauri example validation passed"
