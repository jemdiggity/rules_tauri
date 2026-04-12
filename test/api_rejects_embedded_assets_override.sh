#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$repo_root"

stdout_log=$(mktemp)
stderr_log=$(mktemp)
trap 'rm -f "$stdout_log" "$stderr_log"' EXIT

if bazel query //test/fixtures/tauri_application_api:bad_app >"$stdout_log" 2>"$stderr_log"; then
  echo "expected load failure for removed embedded_assets_rust attribute" >&2
  exit 1
fi

grep -q "embedded_assets_rust" "$stderr_log"
grep -Eq "unexpected keyword|no such attribute" "$stderr_log"

echo "embedded_assets_rust override rejection passed"
