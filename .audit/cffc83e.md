# Post-merge audit: cffc83e

Reviewed landed commits `69117d0` through `cffc83e`: the onchain_evm fork-simulation
docs, the descripex two-segment bound, the 0.4.0 V4 release, task 52's deployed
mainnet Hub/Spoke/Oracle/TokenizationSpoke reads and PositionManager fork writes,
and the reviewer pin of onchain_evm 0.6 so those writes keep account code and
block time.

## Findings and fixes

1. README still documented the onchain_evm 0.5 limits (BlockEnv stuck at
   epoch, `"storage"` overrides clobbering deployed code, "simulate writes
   via anvil") after `cffc83e` pinned 0.6 specifically to lift them. The V4
   fork-write evidence in `deployed_integration_test.exs` already depends on
   fetch-before-amend overrides and a forked BlockEnv. Replaced the stale
   caveats with the 0.6 behavior.
2. `CLAUDE.md` (and therefore `AGENTS.md`) still declared
   `{:onchain_evm, "~> 0.5"}`. Raised it to `~> 0.6`. Regenerating AGENTS.md
   also inlined two include updates that `agents.check` would otherwise fail
   on: LIVE E2E FIRST, and the harness "cross-family is routing doctrine"
   note.
3. CHANGELOG had no Unreleased entries for task 52's deployed V4 evidence or
   the 0.6 pin. Added them, including the lock-side hieroglyph 1.6.2 → 1.7.0
   and rustler → rustler_precompiled refresh that rode with the pin.

No debug output, dead code, hidden test failures, or naming breaks were found
in the landed test. The README install bound `{:onchain_aave, "~> 0.3"}` is
two-segment on purpose and still admits 0.4.0 — left it. The local roadmap
still lists task 52 as `blocked`; that status write is harness-owned and was
not touched. No reviewer rejections were recorded for this range. No follow-up
discoveries warranted an rmap task.

## Verification

- Cold witness: `mix deps.get && mix check.dispatch` passed from the
  intentionally unwarmed worktree. onchain_evm 0.6 loaded via precompiled NIF.
