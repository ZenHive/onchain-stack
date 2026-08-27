---
sha: a3a1d1473feb39463b9c7518d2a59d87f06a431d
short_sha: a3a1d14
audited_at: 2026-08-22
auditor_model: claude-opus-5
verdict: findings-applied
codex_status: unreachable
audited_by: audit-review v1
---

# Audit: ci: remove the GitHub Actions workflows

**Original commit:** a3a1d14 — `ci: remove the GitHub Actions workflows`
**Author:** E.FU
**Files touched:** 2 (`.github/workflows/code-scanning.yml`, `.github/workflows/harness.yml`)
**LOC:** 2 files changed, 136 deletions(-)

This report covers the whole CI-gate lifecycle cluster in the range — `8e29375`,
`84abbf3`, `ceeee37`, `7642254`, `ab1ee64`, `499b5be`, `967f7da`, `7456273` built
the gates up; `a3a1d14` deleted them. The per-commit stubs point here.

## Findings

| # | Pri | Category | File:Line | Description | Resolution |
|---|-----|----------|-----------|-------------|------------|
| 1 | 7 | doc-gap | CLAUDE.md:27 | `mix ci` presented as "the merge bar" with no statement that nothing runs it | applied |
| 2 | 5 | dead-config | .github/dependabot.yml:13-19 | `github-actions` ecosystem watches a now-empty `.github/workflows/` | applied |
| 3 | 6 | dead-config | .circleci/config.yml:1 | Pre-fork (2018) CircleCI config is the only CI-shaped artifact left; weaker gate than `mix ci` | **not applied** — see below |
| 4 | 2 | process | (commit message) | A commit deleting all CI carries no body explaining why | not applied (history) |

## The answer, stated plainly

**This repository has no automated CI.** Verified on the filesystem at `2f4cad7`:

- `.github/` contains only `dependabot.yml`. Both workflows are gone.
- No `.gitlab-ci.yml`, Jenkins, Drone, Woodpecker or Buildkite config exists.
- `git config core.hooksPath` is `~/.git-hooks`, a *developer-machine* dotfiles
  hook set that forwards to the repository's own hooks — and the repository has
  none (`$(git rev-parse --git-common-dir)/hooks` holds only `.sample` files).
  So even the local hook path enforces nothing repo-specific, and `CLAUDE.md`
  already states the commit hook does not run `precommit`.
- `.circleci/config.yml` is the sole remaining CI-shaped file. Its last three
  commits are `08c5118` / `59f7909` / `0ca2649`, all dated 2018-08 and authored
  by Antoine Toulme — the upstream `exthereum/abi` maintainer, years before the
  ZenHive fork. It still uses `working_directory: ~/abi` (the pre-rename path)
  and installs `libtool autoconf libgmp3-dev` to build `libsecp256k1`, which
  this fork does not depend on (no `secp256k1` anywhere in `mix.lock`).

**Every gate therefore survives only in `mix.exs` aliases, run by hand.** Nothing
invokes them on push, on PR, or on merge. The checks the deleted `harness.yml`
ran — format, compile `--warnings-as-errors`, credo `--strict`, doctor, sobelow,
test + 95% coverage, dialyzer — all still exist inside `mix ci` / `mix precommit`,
and `mix ci` is green at HEAD (exit 0, verified this audit). But "the gate exists"
and "the gate runs" are now different statements, and only the first is true.

Two `mix ci` steps are *structurally* unable to run anywhere but this developer's
machine, independent of CI:

- `deps.audit.gated` → `bin/advisory-freshness.sh` in the sibling `onchain-stack`
  checkout.
- `agents.check` → `~/_DATA/code/claude-marketplace/scripts/sync-agents-md.sh`.

`mix.exs`'s own comment (added in `51c84b5`) recorded this honestly for the CI
runner — "both shell out to developer-host scripts that a runner does not have …
and the workflow now says so." The workflow that said so was then deleted, so the
caveat lost its reader. Finding 1 restores it in `CLAUDE.md`, which is where the
harness reviewer (via the generated `AGENTS.md`) will actually see it.

## Finding 3 — why `.circleci/config.yml` was NOT auto-removed

Deleting it is the obvious hygiene fix and it is almost certainly dead. It was not
applied because the one thing that would make deletion *wrong* is unverifiable from
inside the repo: whether the CircleCI project for `ZenHive/hieroglyph` is still
connected. If it is, deleting the config silently removes a running gate — exactly
the failure class this commit already created once. Confirming that needs CircleCI
account access this audit does not have.

Either way it is a finding, and the two branches differ only in the fix:

- **Not connected (expected):** dead inherited config that is the only file in the
  tree still *looking* like CI. Delete it.
- **Connected:** the repo's sole CI runs `mix credo` (not `--strict`), `mix format
  --check-formatted`, `mix test` (no coverage gate) and `mix dialyzer` — a strictly
  weaker set than `mix ci`, with no doctor, sobelow, ex_dna, reach or audit step,
  and it would be green on code `mix ci` would reject. Replace it with `mix ci`.

Escalated to the operator rather than guessed.

## Auto-applied fixes

- `CLAUDE.md`: new paragraph under § "Toolchain & check commands" stating that no
  CI exists, that `.circleci/config.yml` is an unconnected fork-parent artifact,
  that `mix ci` is enforced only by whoever runs it, and that `deps.audit.gated`
  and `agents.check` are developer-host-only — with the instruction that a reviewer
  who cannot reach those paths must say so rather than report a clean `mix ci`.
- `AGENTS.md`: regenerated so the cross-family reviewer sees the above
  (`mix agents.check` re-verified green).
- `.github/dependabot.yml`: removed the dead `github-actions` ecosystem block; the
  `mix` ecosystem block is retained and still meaningful.

## Second-opinion status

Codex was dispatched for this cluster and cancelled ~3 minutes in. Its broker pins
the job workspace root to the primary checkout (`/Users/efries/_DATA/code/hieroglyph`)
with `write: true`, regardless of the working directory named in the prompt — which
conflicts with this audit's hard isolation constraint, since a live harness run holds
that checkout. Cancellation was verified (`running: []`), the job log shows no write
operations, and `git status --porcelain --no-optional-locks` on the primary checkout
is empty at `2f4cad7`. Single-reviewer pass for this cluster.
