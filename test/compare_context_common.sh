#!/bin/sh

compare_context_write_oracle_build_rs() {
    cat >"$1" <<'EOF'
fn main() {
    let attributes = tauri_build::Attributes::new().codegen(tauri_build::CodegenContext::new());
    tauri_build::try_build(attributes).expect("failed to generate Tauri build context");
}
EOF
}

compare_context_add_oracle_tauri_build_dep() {
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

compare_context_prepare_oracle_src_tauri() {
    src_tauri_dir=$1
    compare_context_add_oracle_tauri_build_dep "$src_tauri_dir/Cargo.toml"
    compare_context_write_oracle_build_rs "$src_tauri_dir/build.rs"
}

compare_context_find_unique_context() {
    search_dir=$1
    found_file=$(mktemp)

    find "$search_dir" -path '*/out/tauri-build-context.rs' -print >"$found_file"

    count=$(wc -l <"$found_file" | tr -d ' ')
    if [ "$count" -ne 1 ]; then
        echo "expected exactly one tauri-build-context.rs under $search_dir, found $count" >&2
        cat "$found_file" >&2
        rm -f "$found_file"
        return 1
    fi

    sed -n '1p' "$found_file"
    rm -f "$found_file"
}
