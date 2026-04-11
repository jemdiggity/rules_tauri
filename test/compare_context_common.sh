#!/bin/sh

compare_context_write_oracle_build_rs() {
    cat >"$1" <<'EOF'
fn main() {
    let attributes = tauri_build::Attributes::new().codegen(tauri_build::CodegenContext::new());
    tauri_build::try_build(attributes).expect("failed to generate Tauri build context");
}
EOF
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
