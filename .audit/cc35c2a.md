# Post-merge audit: cc35c2a

## Scope

Reviewed implementation commit `84d0f4652248` and roadmap completion `cc35c2a` for task 4067: PositionManager wrappers, unit and pinned-fork integration tests, README, CHANGELOG, package instructions, and task acceptance criteria. The merge is settled; this audit fixes forward.

## Findings and fixes

1. **Fixed: renounce evidence started from zero allowances.** The fork test consumed the entire approved borrow and withdraw allowances before calling either `renounce_*` wrapper. A no-op renounce could therefore satisfy both zero assertions, despite the module documentation claiming that remaining allowances were cleared. Approvals now grant twice the operation amount. Assertions pin the positive remainder after each operation and zero after each renounce. The borrow remainder accounts for the deployed contract's extra wei of share rounding. Updated the test's module documentation to describe a withdrawal within the allowance.
2. **Follow-up: Mint advisories in the existing dependency lock.** The cold `mix deps.get` reported Mint 1.9.3 advisories EEF-CVE-2026-82728 (HIGH) and EEF-CVE-2026-82729 (MEDIUM). These predate this feature and are distinct from the root instructions' adjudicated gun/cowlib findings. Filed **task 9012** via `rmap new --from-stdin`, assigned to `codex` / `gpt-6-astra`, to verify upstream fixed versions and remediate affected package locks. No dependency upgrades or suppressions were made in this audit.

The new public wrappers have specs and generated API documentation, validate inputs before signing, preserve explicit position owners, and follow the existing routing/error conventions. README, package instructions, and the landed changelog describe the added surface. No dead code, debug output, or additional actionable hygiene findings were found. No reviewer rejections were recorded for this range. The pre-existing absence of tests from the dispatch alias is already tracked by task 9011; no duplicate task was filed.

## Verification

- Cold command: `cd packages/onchain_aave && mix check.dispatch`.
- The first attempt stopped on absent dependencies in the intentionally unwarmed worktree. Ran `mix deps.get` without changing the lock, then reran the dispatch command. An intermediate run caught a newly lengthened test line; split it using the surrounding convention. The final dispatch check **passed**, including formatting, compilation with warnings as errors, Credo, Doctor, clone detection, Reach architecture/smells, and Sobelow. Sobelow emitted its usual no-router warning for this library.
- `cd packages/onchain_aave && mix test test/onchain/aave/v4/position_manager_test.exs test/onchain/aave/v4/deployed_integration_test.exs --include integration`: **38 passed**, including the configured archive RPC and pinned-block EVM fork. The first test run exposed the extra wei consumed from borrow allowance; the corrected assertion passed on rerun.
- `git diff --check`: passed.

Two findings total: one fixed directly and one filed as task 9012. No production code or changelog edits. Roadmap changes are exclusively the discovery filing explicitly requested for this audit.
