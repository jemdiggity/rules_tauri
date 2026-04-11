#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$repo_root"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

bazel aquery --output=text //test/fixtures/tauri_codegen/src-tauri:full_context_rust >"$tmpdir/fixture.aquery"

if ! grep -q "tauri_context_codegen_exec" "$tmpdir/fixture.aquery"; then
    echo "expected full_context_rust to use tauri_context_codegen_exec" >&2
    exit 1
fi

if grep -q -- "--upstream-context-rust" "$tmpdir/fixture.aquery"; then
    echo "expected full_context_rust to stop consuming upstream tauri-build-context.rs" >&2
    exit 1
fi

echo "direct context codegen validation passed"
