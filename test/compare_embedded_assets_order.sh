#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
fixture_dir="$repo_root/test/fixtures/embedded_assets_order"
cd "$repo_root"

expected=$(mktemp)
actual=$(mktemp)
trap 'rm -f "$expected" "$actual"' EXIT

python3 "$fixture_dir/oracle.py" >"$expected"
bazel build --action_env=PATH //test/fixtures/embedded_assets_order:asset_manifest >/dev/null
cp "bazel-bin/test/fixtures/embedded_assets_order/asset_manifest.json" "$actual"

diff -u "$expected" "$actual"
echo "embedded asset ordering comparison passed"
