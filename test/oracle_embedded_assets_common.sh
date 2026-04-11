#!/bin/sh

oracle_embedded_assets_prepare_crate() {
    crate_dir=$1
    fixture_dir=$2
    oracle_build_src=$3
    package_name=$4
    cargo_lock_src=$5
    build_dependencies=$6

    mkdir -p "$crate_dir/src"
    cp "$oracle_build_src" "$crate_dir/oracle_build.rs"
    if [ -n "$cargo_lock_src" ]; then
        cp "$cargo_lock_src" "$crate_dir/Cargo.lock"
    fi
    mkdir -p "$crate_dir/assets"
    cp -R "$fixture_dir/assets/." "$crate_dir/assets/"

    cat >"$crate_dir/Cargo.toml" <<EOF
[package]
name = "$package_name"
version = "0.0.0"
edition = "2021"
build = "oracle_build.rs"

[build-dependencies]
$build_dependencies
EOF

    cat >"$crate_dir/src/lib.rs" <<'EOF'
pub fn placeholder() {}
EOF
}
