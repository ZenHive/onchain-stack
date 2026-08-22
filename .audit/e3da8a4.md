# Audit e3da8a4

Post-merge hygiene pass over `669e413..e3da8a4` (since previous audit `0d6679a`).
Range tip: `e3da8a4` (`roadmap: task 57 -> done`). Detached worktree, cold deps/`_build`.

## Reviewed

36 commits. Substance is four harness deliveries plus the 0.4.0 / 0.5.0 / 0.5.1
releases, the post-audit revm-41 nonce fix, CI removal, and lockfile/docs churn.

| Commit | What landed | Hygiene |
|--------|-------------|---------|
| `669e413` | revm-41 nonce / empty-batch / SpecId-limitation docs | Closes the prior audit's HIGH-tier NIF findings. Sound. |
| `8970f61` / `5bd59c9` / `933327d` | 0.4.0, 0.5.0, 0.5.1 Hex releases | 0.5.1 is published. Features below it belong in Unreleased. |
| `904dfd8` | Task 52 — per-contract `Multicall` helpers | Sound. Missing CHANGELOG / README / SKILL mention. |
| `780ec5c` | Task 59 — parser-frontend spike + characterization test | Sound. Follow-up migration was not filed. |
| `f7fde63` | Task 58 — fork `BlockEnv` + state-override fetch-before-amend | Sound. Missing CHANGELOG. |
| `0a5a05d` + `d2e4d82` | Task 57 — Elixir-boundary option validation | Sound. Docs lagged the new tagged errors / `:from`. |

No leftover debug, no reviewer rejections recorded, no revert/unmerge.

## Findings

| # | Severity | What | Resolution |
|---|----------|------|------------|
| 1 | docs | CHANGELOG Unreleased still claimed `ex_ast` 0.12.10 was blocked (contradicts 0.5.1), restated bandit/cargo notes that already shipped, and omitted tasks 52/57/58/59 | **fixed** |
| 2 | docs | README install pins were `onchain ~> 0.10` / `onchain_evm ~> 0.3`; options table omitted `:from` and Multicall | **fixed** |
| 3 | docs | CLAUDE.md / AGENTS.md still declared `{:onchain, "~> 0.5"}`. SKILL.md still pinned `~> 0.2` / `~> 0.8` and stale rpc_url tags (`:not_http`, `:no_host`) | **fixed** |
| 4 | convention | Harness `check_command` is `mix check.dispatch`; the alias did not exist (family sibling `onchain_aave` already has it) | **fixed** |
| 5 | follow-up | Task 59 recommended migrating `parse_sol` to `solar-parse` and scored it D:6/B:8/U:7; no rmap task existed | **filed** as task 61 on the project roadmap |

Task 29's AC that pins solang-parser rejection of `transient` is now satisfied by
the Task 59 characterization test. Left untouched (append-only); the migration
in task 61 inverts that test.

## Fixed

- CHANGELOG Unreleased rewritten for the four landed features; 0.5.1 Security
  notes the bandit 1.12.5 lock that actually shipped with that tag.
- README install pins, option table, and Multicall sentence.
- CLAUDE.md toolchain (`mix check.dispatch` vs `mix ci`) and onchain bound;
  AGENTS.md regenerated.
- SKILL.md pins, rpc_url reasons, validation error tags, Multicall.
- `mix.exs` `check.dispatch` alias (format, compile --warnings-as-errors,
  credo --strict, doctor, ex_dna, reach --arch --smells, sobelow --skip --exit low).

## Cold check

`mix check.dispatch` on this un-warmed tree: **passed** (exit 0). Compiled both
NIFs from a cold Cargo cache, then credo / doctor / ex_dna / reach / sobelow
were clean.

## Filed

Task 61 — *Migrate Solidity source parsing from solang-parser to solar-parse*
(`[D:6/B:8/U:7]`, depends_on 59, `cursor` / `cursor-grok-4.6-high`).
