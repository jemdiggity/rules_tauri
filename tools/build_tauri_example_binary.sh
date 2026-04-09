#!/bin/sh
set -eu

if [ "$#" -ne 5 ]; then
  echo "usage: $0 <app_src_dir> <frontend_dist_dir> <target_triple> <binary_name> <output_path>" >&2
  exit 1
fi

app_src_dir=$1
frontend_dist_dir=$2
target_triple=$3
binary_name=$4
output_path=$5
exec_root=$(pwd)

if [ -n "${CARGO_BIN:-}" ]; then
  cargo_bin=$CARGO_BIN
elif cargo_bin=$(command -v cargo 2>/dev/null); then
  :
else
  echo "error: cargo not found in PATH; set CARGO_BIN or install cargo" >&2
  exit 1
fi

case "$output_path" in
  /*) ;;
  *) output_path="$exec_root/$output_path" ;;
esac

case "$frontend_dist_dir" in
  /*) ;;
  *) frontend_dist_dir="$exec_root/$frontend_dist_dir" ;;
esac

workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT INT TERM

app_copy="$workdir/app"
cp -RL "$app_src_dir" "$app_copy"
chmod -R u+w "$app_copy"

rm -rf "$app_copy/dist"
mkdir -p "$app_copy/dist"
cp -RL "$frontend_dist_dir/." "$app_copy/dist"

cd "$app_copy/src-tauri"
CARGO_TARGET_DIR="$workdir/target" "$cargo_bin" build \
  --release \
  --target "$target_triple" \
  --features tauri/custom-protocol \
  --bins \
  >/dev/null

mkdir -p "$(dirname "$output_path")"
cp "$workdir/target/$target_triple/release/$binary_name" "$output_path"
chmod 755 "$output_path"
