#!/bin/sh

. "$(CDPATH= cd -- "$(dirname "$0")" && pwd)/oracle_build_common.sh"

compare_context_prepare_oracle_src_tauri() {
    src_tauri_dir=$1
    oracle_build_prepare_src_tauri "$src_tauri_dir"
}

compare_context_stage_oracle_workspace() {
    fixture_src_tauri=$1
    fixture_dist=$2
    oracle_root=$3

    mkdir -p "$oracle_root"
    cp -R "$fixture_src_tauri" "$oracle_root/src-tauri"
    cp -R "$fixture_dist" "$oracle_root/dist"
    compare_context_prepare_oracle_src_tauri "$oracle_root/src-tauri"
}

compare_context_build_oracle_workspace() {
    oracle_root=$1
    target_dir=$2

    (
        cd "$oracle_root/src-tauri"
        CARGO_TARGET_DIR="$target_dir" cargo build --quiet >/dev/null
    )
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
