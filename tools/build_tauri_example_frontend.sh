#!/bin/sh
set -eu

if [ "$#" -ne 2 ] && [ "$#" -ne 3 ]; then
  echo "usage: $0 [<bun_bin>] <app_src_dir> <output_dir>" >&2
  exit 1
fi

if [ "$#" -eq 3 ]; then
  bun_bin=$1
  app_src_dir=$2
  output_dir=$3
elif [ -n "${BUN_BIN:-}" ]; then
  bun_bin=$BUN_BIN
  app_src_dir=$1
  output_dir=$2
elif bun_bin=$(command -v bun 2>/dev/null); then
  app_src_dir=$1
  output_dir=$2
else
  echo "error: bun not found in PATH; set BUN_BIN or install bun" >&2
  exit 1
fi

exec_root=$(pwd)

case "$bun_bin" in
  /*) ;;
  *) bun_bin="$exec_root/$bun_bin" ;;
esac

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
