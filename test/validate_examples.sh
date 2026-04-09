#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$repo_root"

bazel build \
  //examples/minimal_macos:bundle_inputs_arm64 \
  //examples/minimal_macos:app_arm64 \
  //examples/minimal_macos:bundle_inputs_x86_64 \
  //examples/minimal_macos:app_x86_64

arm64_app="$repo_root/bazel-bin/examples/minimal_macos/app_arm64.app"
x86_app="$repo_root/bazel-bin/examples/minimal_macos/app_x86_64.app"

test -f "$arm64_app/Contents/Info.plist"
test -f "$arm64_app/Contents/MacOS/minimal-app"
test -f "$arm64_app/Contents/MacOS/helper-sidecar"
test -f "$arm64_app/Contents/Resources/frontend/examples/minimal_macos/src/frontend/index.html"
test -f "$arm64_app/Contents/Resources/resources/examples/minimal_macos/src/resources/example.txt"
test -f "$arm64_app/Contents/Resources/legal/license.txt"
test -f "$arm64_app/Contents/Resources/AppIcon.icns"
test -f "$arm64_app/Contents/Frameworks/Fake"
test -f "$arm64_app/Contents/Helpers/extra.conf"

test -f "$x86_app/Contents/Info.plist"
test -f "$x86_app/Contents/MacOS/minimal-app"
test -f "$x86_app/Contents/MacOS/helper-sidecar"

echo "rules_tauri example validation passed"
