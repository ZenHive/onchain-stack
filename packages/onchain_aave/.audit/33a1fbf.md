# Post-merge audit: 33a1fbf

Reviewed landed commits `6531bef` through `33a1fbf`, covering the mutation,
property, and REVM differential suites; pinned V3/V4 fixtures and provenance;
support modules; user-facing documentation; and the task-completion metadata.

## Findings and fixes

1. Four test-support helpers were unreferenced: `goldens_path/0`,
   `write_ledger!/1`, `bytecode_ops/0`, and `display_ops/0`. Removed them.
2. Task 56's mutation-grade math verification had no changelog entry. Added a
   concise summary under `Unreleased`.
3. The fixture README said a trailing newline would fail the bytecode checksum,
   but the loader trims whitespace before hashing. Clarified the difference
   between the loader's normalized hash and `shasum` over raw bytes.
4. The generic commit hook invoked raw `mix deps.audit`, bypassing the project's
   reviewed advisory ignore file and blocking on a documented multi-package
   advisory false positive. Made the raw task alias apply `.mix_audit_ignore`,
   while `deps.audit.gated` still proves advisory freshness before invoking it.

No debug output, stale naming, hidden test failures, or other convention breaks
were found. No reviewer rejections were recorded for this range.

## Verification

- Cold witness: `mix deps.get && mix check.dispatch` passed from the intentionally
  unwarmed worktree.
- Pre-edit offline coverage: `mix test.json --cover --quiet --output
  /tmp/onchain_aave_audit_33a1fbf_coverage.json` passed 381 tests with 99.85%
  total production coverage; 67 integration-tagged tests were excluded. Both
  `Onchain.Aave.Math` modules reported 100% coverage.
- Post-fix focused tests: mutation and property suites passed 11/11.
- Post-fix `mix check.dispatch` passed.
- `mix deps.audit` and `mix deps.audit.gated` passed with the repository's
  reviewed advisory policy.

No follow-up discoveries warranted an rmap task.
