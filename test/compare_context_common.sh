#!/bin/sh

compare_context_common_dir=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
. "$compare_context_common_dir/oracle_build_common.sh"

compare_context_overlay_oracle_manifest() {
    src_tauri_dir=$1
    oracle_fixture_dir=$2

    cp "$oracle_fixture_dir/Cargo.toml" "$src_tauri_dir/Cargo.toml"
    cp "$oracle_fixture_dir/Cargo.lock" "$src_tauri_dir/Cargo.lock"
    cp "$oracle_fixture_dir/empty.rs" "$src_tauri_dir/empty.rs"
    rm -rf "$src_tauri_dir/src"
    oracle_build_write_build_rs "$src_tauri_dir/build.rs"
}

compare_context_stage_oracle_workspace() {
    fixture_src_tauri=$1
    fixture_dist=$2
    oracle_root=$3
    oracle_fixture_dir="$compare_context_common_dir/fixtures/tauri_codegen/oracle_src-tauri"

    mkdir -p "$oracle_root"
    cp -R "$fixture_src_tauri" "$oracle_root/src-tauri"
    cp -R "$fixture_dist" "$oracle_root/dist"
    compare_context_overlay_oracle_manifest "$oracle_root/src-tauri" "$oracle_fixture_dir"
}

compare_context_build_oracle_workspace() {
    oracle_root=$1
    target_dir=$2

    (
        cd "$oracle_root/src-tauri"
        CARGO_TARGET_DIR="$target_dir" cargo build --quiet --locked >/dev/null
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
