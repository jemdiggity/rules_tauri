#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$repo_root"

path_for() {
  bazel cquery --output=starlark --starlark:expr='target.files.to_list()[0].path' "$1"
}

bazel build \
  //test/fixtures/frontend_dist:dist \
  //test/fixtures/frontend_dist:normalized_dir \
  //test/fixtures/frontend_dist:normalized_files

dist_path="$repo_root/$(path_for //test/fixtures/frontend_dist:dist)"
normalized_dir_path="$repo_root/$(path_for //test/fixtures/frontend_dist:normalized_dir)"
normalized_files_path="$repo_root/$(path_for //test/fixtures/frontend_dist:normalized_files)"

test "$dist_path" = "$normalized_dir_path"

test -f "$normalized_files_path/index.html"
test -f "$normalized_files_path/assets/app.js"
test -f "$normalized_files_path/styles/base.css"

echo "frontend_dist normalization validation passed"
