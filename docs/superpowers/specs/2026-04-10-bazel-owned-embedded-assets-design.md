# Bazel-Owned Embedded Assets Design

## Goal

Replace the embedded-asset generation portion of Tauri compile-time behavior with Bazel-owned, deterministic generation while leaving Tauri runtime behavior intact.

This is the first step toward a model where Tauri is primarily a runtime dependency and Bazel owns the compile-time preparation around it.

## Why This Slice First

The current realistic example is already in a decent state:

- Bazel builds the frontend with `rules_js`
- Bazel builds the Rust binary with `rules_rust`
- `rules_tauri` assembles the unsigned macOS `.app`

The remaining non-Bazel compile-time behavior is concentrated in `tauri-build` / `tauri-codegen`.

Within that area, embedded asset generation is the best first seam to replace because:

- it has a clear input boundary: `frontend_dist`
- it has a clear output boundary: generated Rust for embedded assets
- it is directly relevant to determinism and hermeticity
- it can be measured independently of the rest of Tauri context generation

Replacing all of `tauri-codegen` at once would be much riskier and harder to validate.

## Design Principle

Decompose Tauri compile-time behavior into seams and add a fixture for each seam that can be compared against upstream output.

The long-term seam ladder is:

1. asset discovery and stable ordering
2. asset content transforms
3. embedded asset Rust generation
4. build-script handoff into Rust compilation
5. ACL / capability generation
6. full context generation

This design covers only seams 1 through 3.

## Phase 1 Scope

Phase 1 adds Bazel-owned behavior for:

1. deterministic asset enumeration from `frontend_dist`
2. deterministic embedded-bytes Rust generation
3. fixture-based comparison against current upstream Tauri output at those seams

Phase 1 does not yet replace:

- full `tauri_build::try_build(...)`
- ACL/capability generation
- full `tauri-build-context.rs` generation
- bundle assembly semantics already handled elsewhere

## Source Of Truth

The primary behavioral reference remains the local Tauri checkout at:

- `/Users/jeremyhale/.kanna/repos/tauri`

Relevant upstream files:

- `crates/tauri-codegen/src/embedded_assets.rs`
- `crates/tauri-codegen/src/context.rs`
- `crates/tauri-utils/src/html2.rs`
- `crates/tauri-utils/src/config.rs`

## Fixture Strategy

Every seam we replace must get its own tiny fixture and comparison test.

Each seam fixture should have:

- minimal source inputs
- one Bazel-produced output
- one upstream-produced reference output
- one narrow comparison script/test

The fixture should be as small as possible so failures are attributable to one seam, not the whole desktop app.

### Fixture Types

#### 1. Asset Ordering Fixture

Purpose:
- prove Bazel enumerates files with stable normalized ordering

Inputs:
- a tiny directory tree with nested files and mixed extensions

Outputs:
- a manifest or JSON description of discovered assets

Comparison:
- compare Bazel ordering against an upstream-derived reference ordering

#### 2. Asset Transform Fixture

Purpose:
- measure any HTML/script/CSP-related rewrites independently

Inputs:
- minimal HTML/JS assets with inline script/style cases

Outputs:
- transformed asset bytes or hashes

Comparison:
- compare Bazel output vs upstream transformed result

This seam may initially be read-only if we decide to postpone replacing transforms.

#### 3. Embedded Rust Generation Fixture

Purpose:
- prove Bazel can generate deterministic Rust source representing embedded assets

Inputs:
- a known frontend asset tree

Outputs:
- generated Rust source or token-equivalent file

Comparison:
- compare Bazel-generated structure and embedded bytes against upstream output

## Output Model

The Bazel-owned replacement should produce explicit intermediate artifacts, not hide work inside a build script.

Recommended outputs:

- asset manifest describing normalized asset paths
- generated Rust source file for embedded assets

That source file should be consumable by a Rust target or by a later Tauri-context generation step.

This keeps the seam measurable and makes determinism review possible.

## Determinism Requirements

The Bazel-owned embedded-assets path should be stricter than upstream Tauri.

Requirements:

- stable file ordering
- stable path normalization
- no random IDs
- no dependency on filesystem iteration order
- no dependency on host temp paths in generated output
- byte-stable generated Rust for identical inputs

If upstream output is not byte-stable, the fixture should compare semantic equivalence first and then document where Bazel is intentionally stricter.

## Integration Strategy

The integration path should be incremental:

1. build seam fixtures first
2. make Bazel embedded-asset generation pass those comparisons
3. wire the generated Rust output into the existing isolated `tauri_codegen` fixture
4. once that is green, wire it into `examples/tauri_with_vite`

The realistic example should not be the primary debug target for early seam work.

## Public API Impact

No public `rules_tauri` API change is required in phase 1.

This should remain implementation detail while we validate the seam replacement.

If a public API change becomes necessary later, it should be justified by a broader context-generation design rather than by the first seam alone.

## Proposed File Direction

Likely additions:

- `tools/tauri_assets_manifest.py`
- `tools/tauri_embedded_assets_rust.py`
- seam fixtures under `test/fixtures/`
- seam comparison scripts under `test/`

Likely modifications:

- existing isolated `test/fixtures/tauri_codegen` targets
- example wiring only after the seam fixtures pass

The exact tool language can remain Python initially if that keeps the seam easy to inspect and test.

## Verification

Phase 1 is complete when all of the following are true:

- a narrow asset-ordering fixture passes
- a narrow embedded-Rust-generation fixture passes
- the existing `test/fixtures/tauri_codegen` path can consume Bazel-generated embedded asset source
- existing repository checks remain green

Minimum verification commands:

- `./test/validate_rules_rust_codegen_fixture.sh`
- seam-specific comparison tests to be added
- `./test/validate_examples.sh`

The parity script for the full example should remain green throughout, but it is a secondary confirmation for this phase.

## Risks

- upstream Tauri transforms may be more coupled to the rest of context generation than they first appear
- semantic equivalence may matter more than byte-for-byte identity for some upstream outputs
- fixture design must stay narrow, or failures will become ambiguous

## Recommendation

Start with the smallest deterministic seam:

- asset discovery/order
- then embedded Rust source generation

Defer full HTML/CSP transform replacement until we have fixture evidence that it is needed or straightforward.

That keeps the work measurable, incremental, and aligned with the goal of turning Tauri into primarily a runtime dependency.
