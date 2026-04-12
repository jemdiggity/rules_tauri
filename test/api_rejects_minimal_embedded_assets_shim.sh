#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$repo_root"

stdout_log=$(mktemp)
stderr_log=$(mktemp)
trap 'rm -f "$stdout_log" "$stderr_log"' EXIT

if bazel query //examples/minimal_macos:embedded_assets_rust >"$stdout_log" 2>"$stderr_log"; then
  echo "expected minimal embedded assets shim to be removed" >&2
  exit 1
fi

grep -q "embedded_assets_rust" "$stderr_log"
grep -Eq "target 'embedded_assets_rust' not declared|no such target" "$stderr_log"

echo "minimal embedded assets shim rejection passed"
