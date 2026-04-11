# Full Semantic Bazelfication Design

## Goal

Remove upstream Tauri compile-time code from the active Bazel release path so `rules_tauri` owns release-path semantics end-to-end, while keeping behaviorally equivalent outputs and preserving fixture-driven upstream oracles for each seam we replace.

## Non-Goals

- Changing the public API in `//tauri:defs.bzl` or `//tauri:providers.bzl`
- Expanding `rules_tauri` beyond unsigned macOS `.app` assembly
- Requiring byte-for-byte equality with upstream-generated intermediate files
- Removing every upstream oracle immediately
- Broad repository refactors unrelated to the remaining compile-time seams

## Recommended Approach

Keep the current private Bazel pipeline shape, but replace the remaining upstream `tauri-codegen` semantics incrementally inside repo-owned tools. Every semantic cut must be preceded by a dedicated fixture oracle that captures the upstream behavior for that seam.

That means:

1. `tools/tauri_context_codegen` stops being a thin wrapper around upstream `tauri-codegen` and becomes a repo-owned semantic generator.
2. `tools/tauri_acl_prep` remains the ACL/capability producer and can absorb more upstream behavior only when that behavior has a fixture oracle first.
3. `private/upstream_context_oracle.bzl` remains the orchestration layer, but its helpers eventually stop depending on upstream Tauri compile-time crates for active Bazel release outputs.
4. The fixture remains the narrow upstream oracle surface, but each remaining semantic seam gets its own explicit comparison test before we replace it.

This keeps the active release path fully Bazel-owned without requiring a high-risk big-bang rewrite.

## Architecture

### Current split

Today the pipeline is mostly Bazel-owned in orchestration, but not yet fully Bazel-owned in semantics:

- Bazel owns the rule graph, inputs, outputs, and staging flow.
- `tools/tauri_acl_prep` already reproduces ACL preparation behavior in a Bazel exec tool.
- `tools/tauri_context_codegen` still calls `tauri_codegen::get_config(...)` and `tauri_codegen::context_codegen(...)`.
- The real example is helper-free, but the fixture still acts as the narrow upstream oracle.

The remaining upstream compile-time dependency is therefore concentrated in the context-generation seam.

### Target end state

The active Bazel release path should look like this:

1. Bazel resolves all explicit inputs:
   - `tauri.conf.json`
   - icons
   - capabilities
   - frontend assets
   - generated ACL outputs
2. Bazel exec tools produce:
   - ACL/capability side outputs
   - the full `tauri-build-context.rs`
   - any required side artifacts currently expected by the release path
3. The real example `build.rs` remains only a thin staging/compatibility layer for Cargo-facing expectations.
4. No active Bazel release target calls upstream `tauri-build` or `tauri-codegen`.

Upstream behavior remains available only through the fixture oracle path used for comparison tests.

### Seam decomposition

The remaining semantic work should be split into independent seams, each with its own oracle:

1. **Config loading and normalization**
   Replace upstream config parsing/merging behavior used by `tauri_codegen::get_config(...)`.

2. **Context assembly**
   Replace upstream generation of the `tauri-build-context.rs` expression, but only for the subset of semantics required by the repository’s supported release contract.

3. **Embedded-assets integration boundary**
   Preserve the already-Bazel-owned embedded-assets seam and ensure the repo-owned context generator consumes it directly.

4. **ACL/context joining**
   Preserve and tighten the contract between ACL outputs and full-context generation so the context generator never relies on ambient state.

Each seam should be replaced only after a fixture oracle proves we understand the upstream behavior we are taking ownership of.

## Oracle Strategy

This is the core rule for the remaining work:

**No semantic replacement without a dedicated fixture oracle first.**

The fixture oracles should be narrow and seam-specific, not only end-to-end.

For each seam:

1. Add a focused fixture comparison that captures upstream behavior for that seam.
2. Run it against the current upstream-backed baseline and verify it passes.
3. Switch only that seam to repo-owned logic.
4. Re-run the focused oracle until it passes again.
5. Keep the broader guardrails green:
   - fixture validation
   - full-context comparison
   - context build-config comparison
   - ACL/runtime-authority comparisons
   - real example validation
   - cargo-vs-Bazel parity

Examples of seam-level oracle outputs that are appropriate:

- normalized config values consumed by context generation
- specific context fields or subexpressions relevant to runtime behavior
- file/path normalization semantics
- integration of ACL/capability outputs into generated context

Examples that are not required:

- byte-for-byte equality for every generated file
- preservation of unused upstream implementation details
- upstream behavior outside the repository’s release contract

## Behavior Standard

The target is **behavioral equivalence**, not byte-for-byte identity.

That means the repo-owned implementation may differ internally as long as:

- the built `.app` behaves the same for the supported contract
- the generated context provides equivalent runtime semantics for the example and fixture
- the existing parity and seam tests remain green

This is important because a fully repo-owned generator should not be forced to preserve arbitrary upstream formatting, AST structure, or incidental intermediate naming if those details do not affect the supported release path.

## File Responsibilities

### `tools/tauri_context_codegen/src/main.rs`

This becomes the main semantic replacement target.

It should evolve from:

- reading config through upstream helpers
- generating context through upstream helpers

to:

- reading and normalizing explicit inputs directly
- constructing only the supported context semantics directly
- consuming Bazel-owned embedded-assets and ACL outputs without ambient assumptions

### `tools/tauri_acl_prep/src/main.rs`

This remains the Bazel-owned ACL seam.

It may absorb additional upstream behavior only if:

- the behavior is part of the supported release contract
- the seam has a dedicated upstream oracle first
- the new logic stays deterministic and explicit about inputs

### `private/upstream_context_oracle.bzl`

This remains private orchestration only.

It should continue to:

- wire explicit inputs into Bazel exec tools
- isolate the fixture oracle path from the active release path
- avoid broadening the public API

Over time it should lose assumptions that the active path needs upstream Tauri compile-time crates.

### Fixture and test scripts

The test directory should gain seam-specific comparison scripts and fixture inputs as needed. These tests are not optional scaffolding; they are the control system for the migration.

## Risks

### Hidden semantic scope

`tauri-codegen` contains more behavior than the repo actually needs. The biggest risk is accidentally trying to reimplement upstream surface area that does not matter to `rules_tauri`.

Mitigation:

- define seam scope narrowly
- prove each seam with an oracle before replacing it
- stop at behavior required by the supported release contract

### Oracle gaps

If a seam is replaced before it has a narrow oracle, regressions will first appear in the larger end-to-end tests, which slows debugging and weakens confidence.

Mitigation:

- require a new fixture oracle before each semantic replacement
- treat missing seam-level coverage as a blocker, not a follow-up

### Ambient-input regression

The upstream code relies on env vars, cwd, and path conventions. A partial rewrite can accidentally preserve those hidden assumptions.

Mitigation:

- make every new tool input explicit in Bazel
- avoid ambient cwd/env lookups except where the tool boundary intentionally models them
- prefer serialized fixture inputs over implicit discovery

### Scope creep

“Rewrite `tauri-codegen` in Bazel” can grow into “replace all upstream Tauri semantics everywhere.”

Mitigation:

- keep the scope bounded to the active release path
- preserve upstream fixture oracles until repo-owned semantics are proven
- avoid public API changes unless a true contract gap appears

## Success Criteria

This work is complete when:

- the active Bazel release path no longer calls upstream `tauri-build` or `tauri-codegen`
- the remaining repo-owned compile-time semantics are produced by Bazel exec tools under `//tools`
- every replaced seam was introduced through a dedicated fixture oracle before replacement
- the fixture remains a working upstream oracle for comparison where still needed
- the repository’s current verification suite stays green
- no public `rules_tauri` API changes are required

## Recommended Execution Order

1. Add a seam oracle for config loading/normalization.
2. Replace that seam in `tools/tauri_context_codegen`.
3. Add a seam oracle for context assembly behavior that matters to runtime output.
4. Replace that seam in `tools/tauri_context_codegen`.
5. Remove the remaining upstream `tauri-codegen` dependency from the active Bazel path.
6. Keep the fixture/example/full parity matrix green at each cut.
