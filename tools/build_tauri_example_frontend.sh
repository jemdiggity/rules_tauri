#!/bin/sh
set -eu

if [ "$#" -ne 2 ]; then
  echo "usage: $0 <app_src_dir> <output_dir>" >&2
  exit 1
fi

app_src_dir=$1
output_dir=$2
exec_root=$(pwd)

if [ -n "${BUN_BIN:-}" ]; then
  bun_bin=$BUN_BIN
elif bun_bin=$(command -v bun 2>/dev/null); then
  :
else
  echo "error: bun not found in PATH; set BUN_BIN or install bun" >&2
  exit 1
fi

case "$output_dir" in
  /*) ;;
  *) output_dir="$exec_root/$output_dir" ;;
esac

workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT INT TERM

app_copy="$workdir/app"
cp -RL "$app_src_dir" "$app_copy"
chmod -R u+w "$app_copy"

cd "$app_copy"
"$bun_bin" install >/dev/null
"$bun_bin" run build >/dev/null

mkdir -p "$output_dir"
cp -RL "$app_copy/dist/." "$output_dir"
