#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$repo_root"

bazel build //test/fixtures/embedded_assets_rust:embedded_assets_rust >/dev/null
