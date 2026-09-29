---
sha: d636328e0a13bb7a29dda468c154f4d4e44b636d
short_sha: d636328
audited_at: 2026-08-22
auditor_model: claude-opus-5
verdict: findings-applied
codex_status: unreachable
audited_by: audit-review v1
---

# Audit: deps: widen the descripex bound to two segments

**Original commit:** d636328 · **Author:** E.FU · **LOC:** 1 file, 7 insertions(+), 6 deletions(-)

Promoted out of the tiny-commit fast path at the operator's request: the bound
ships in the published package, so it is a consumer-visible change regardless of
diff size. Audited together with `97921d9` (the 1.6.2 release that carries it).

## Findings

| # | Pri | Category | File:Line | Description | Resolution |
|---|-----|----------|-----------|-------------|------------|
| 1 | 5 | test gap | test/abi/agent_economy_test.exs | Nothing pins the `describe/1` output *shape* the widened bound now admits drift in | **escalated — not fixed** |

## Does the widened bound match what the code relies on?

The change is `{:descripex, "~> 0.12.0"}` → `{:descripex, "~> 0.12"}`, i.e. from
`>= 0.12.0 and < 0.13.0` to `>= 0.12.0 and < 1.0.0`.

What the code actually consumes (verified by grep, not assumed):

| Surface | Sites |
|---|---|
| `use Descripex, namespace: …` | `lib/abi.ex:22`, `abi/event.ex:10`, `abi/math.ex:6`, `abi/type_encoder.ex:8`, `abi/type_decoder.ex:9`, `abi/function_selector.ex:7` |
| `use Descripex.Discoverable` | `lib/abi.ex:24` |
| `Descripex.Manifest` | `lib/mix/tasks/hieroglyph.manifest.ex:22` |
| generated `describe/0..2`, `__descripex_modules__/0`, `__api__/0..1` | public surface + `test/abi/agent_economy_test.exs` |
| dialyzer PLT | `mix.exs:34` (`plt_add_apps: [:mix, :descripex]`) |

This is a **macro-level** dependency: `use Descripex` generates the public
introspection functions, and `mix hieroglyph.manifest` emits `api_manifest.json`
from them — an artifact the README explicitly offers to downstream cartouche /
onchain CI as a contract-stability check. So the surface at risk is not a function
call this library makes, but the *shape of what it publishes*.

**The reasoning in the commit is sound and the widening is correct.** The
three-segment cap ships inside the published package, so it capped consumers
transitively: a hieroglyph consumer could not resolve descripex 0.13.0 no matter
what its own bound said. In-family it protected nothing, because `mix.lock` is
committed and a new descripex only arrives via a deliberate `mix deps.update`
behind `mix ci`. Widening cannot break a resolution that previously succeeded, so
shipping it as a patch is right. Verified against 0.13.0: the lock moved
0.12.1 → 0.13.0 and `mix ci` is green at HEAD.

## Finding 1 — the residual gap

The cap existed because descripex 0.12.0 changed `short_name` in `describe/1`
output from an atom to a string *at a minor bump*. Removing the cap moves that
risk from "blocked by the bound" to "caught by the suite" — but `mix.lock` only
protects **this** repo. A downstream consumer resolving fresh gets any descripex
satisfying `~> 0.12`, and a future minor that reshapes `describe/1` output would
silently shift hieroglyph's published agent-introspection surface without any
version bump here.

`test/abi/agent_economy_test.exs` asserts that the discovery surface *exists*
(every `__api__/0` entry carries `:hints.description`; `describe/0..2` returns the
expected modules and function lists; namespaces match). It does not pin the
**shape** of the emitted values — which is exactly what changed at 0.12.0.

Not auto-applied: choosing what to pin (a golden `api_manifest.json` diff, a
type-shape assertion on `describe/1`, or a narrower per-key check) is a design
call about how tightly to couple to a 0.x dependency's output, and the wrong
choice makes every benign descripex release a red suite. Flagged for the operator.

## Release-metadata consistency (covers 97921d9)

- `mix.exs` version `1.6.2`, CHANGELOG top entry `# 1.6.2 - 2026-08-22` — agree.
- `mix.lock` carries descripex 0.13.0, matching the CHANGELOG's "Verified against
  descripex 0.13.0".
- The CHANGELOG's "426 tests, 96.6% coverage" was measured at 97921d9; HEAD reads
  458 tests / 98.88% because `6fd584a` landed the corpus suite afterwards. Not a
  discrepancy — the numbers describe different commits.
- No stray version string elsewhere (`README.md` uses `~> 1.0`, which is correct
  for a consumer-facing install line).

## Auto-applied fixes

- (none in this commit's own files)

## Second-opinion status

Codex was dispatched for this cluster and cancelled — broker pins the workspace
root to the primary checkout with write access, incompatible with this audit's
isolation constraint. Single-reviewer pass.
