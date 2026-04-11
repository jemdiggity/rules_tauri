#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
app_root="$repo_root/examples/tauri_with_vite/app"
src_tauri_dir="$app_root/src-tauri"
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
oracle_app="$tmpdir/app"
oracle_src_tauri="$oracle_app/src-tauri"

cp -R "$app_root" "$oracle_app"

cat >"$oracle_src_tauri/build.rs" <<'EOF'
fn main() {
    let attributes = tauri_build::Attributes::new().codegen(tauri_build::CodegenContext::new());
    tauri_build::try_build(attributes).expect("failed to generate Tauri build context");
}
EOF

python3 - "$oracle_src_tauri/Cargo.toml" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
marker = "[build-dependencies]\n"
replacement = marker + 'tauri-build = { version = "2", features = ["codegen"] }\n'
if replacement in text:
    raise SystemExit(0)
if marker not in text:
    raise SystemExit("missing [build-dependencies] section")
path.write_text(text.replace(marker, replacement, 1), encoding="utf-8")
PY

cd "$oracle_app"
pnpm install --frozen-lockfile
pnpm build

cd "$oracle_app"
pnpm exec tauri build --bundles app

upstream_app="$oracle_src_tauri/target/release/bundle/macos/tauri-with-vite.app"
cd "$repo_root"
bazel build --action_env=PATH //examples/tauri_with_vite:app_arm64 >/dev/null
bazel_app="$repo_root/bazel-bin/examples/tauri_with_vite/app_arm64.app"

test -d "$upstream_app"
test -d "$bazel_app"

upstream_exe="$upstream_app/Contents/MacOS/tauri-with-vite"
bazel_exe=$(find -L "$bazel_app/Contents/MacOS" -maxdepth 1 -type f | head -n 1)

test -f "$upstream_exe"
test -f "$bazel_exe"
test ! -e "$bazel_app/Contents/Resources/frontend"
test "$(basename "$upstream_exe")" = "$(basename "$bazel_exe")"
strings "$upstream_exe" | grep -q "/assets/index-"
strings "$upstream_exe" | grep -q "/vite.svg"
strings "$bazel_exe" | grep -q "/assets/index-"
strings "$bazel_exe" | grep -q "/vite.svg"

echo "tauri parity comparison passed"
