#!/bin/sh

oracle_build_write_build_rs() {
    cat >"$1" <<'EOF'
fn main() {
    let attributes = tauri_build::Attributes::new().codegen(tauri_build::CodegenContext::new());
    tauri_build::try_build(attributes).expect("failed to generate Tauri build context");
}
EOF
}

oracle_build_add_tauri_build_dep() {
    python3 - "$1" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
marker = "[build-dependencies]\n"
replacement = marker + 'tauri-build = { version = "2", features = ["codegen"] }\n'
if 'tauri-build = { version = "2", features = ["codegen"] }\n' in text:
    raise SystemExit(0)
if marker not in text:
    raise SystemExit("missing [build-dependencies] section")
path.write_text(text.replace(marker, replacement, 1), encoding="utf-8")
PY
}

oracle_build_prepare_src_tauri() {
    src_tauri_dir=$1
    oracle_build_add_tauri_build_dep "$src_tauri_dir/Cargo.toml"
    oracle_build_write_build_rs "$src_tauri_dir/build.rs"
}
