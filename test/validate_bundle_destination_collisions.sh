#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$repo_root"

stdout_log=$(mktemp)
stderr_log=$(mktemp)
trap 'rm -f "$stdout_log" "$stderr_log"' EXIT

if bazel build --action_env=PATH //test/fixtures/bundle_collision:bundle_inputs >"$stdout_log" 2>"$stderr_log"; then
  echo "expected duplicate bundle destinations to fail" >&2
  exit 1
fi

grep -q "duplicate manifest destination" "$stderr_log"
grep -q "Helpers/duplicate.txt" "$stderr_log"

echo "bundle destination collision validation passed"
