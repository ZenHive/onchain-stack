<!-- Auto-generated from CLAUDE.md by claude-marketplace/scripts/sync-agents-md.sh — do not edit manually -->

# Onchain Stack — Coordination Home

This folder is a **coordination cockpit** for the onchain package family, not a
container. The repos live where they always have — `~/_DATA/code/<repo>/` — and
under Hex dependencies their on-disk location is irrelevant. You operate from
*here* to drive **cross-repo updates and Hex publish-preparation**; each repo's
own `CLAUDE.md` still governs work *inside* that repo.

**Publishing is a manual human step (Hex 2FA).** Your job ends at *publish-ready*:
green suite, bumped version, updated CHANGELOG, committed, pushed. The human runs
`mix hex.publish` and enters the 2FA code. Never assume a package is on Hex
because the local tree looks done — **verify against Hex** (see Operating Rules).

This document is self-contained on purpose: it must be readable by **any** agent
(Claude, Codex, Cursor, Grok). After editing it, regenerate `AGENTS.md` with
`~/_DATA/code/claude-marketplace/scripts/sync-agents-md.sh` (run from this folder).

---

## The family (10 managed repos — all Hex packages)

Two tiers. The **shared upstreams** (descripex, zen_websocket) are first-party and
sit at the top of the cascade, but they're consumed *beyond* this family too — a
publish there has a wider blast radius than a family-internal one. Flag that when
you release them. The **onchain family** proper is the connected dependency cascade.

**Shared upstreams** (first-party, used beyond this family):

| Repo | Path | Hex package | Local ver | Role | Native |
|---|---|---|---|---|---|
| descripex | `~/_DATA/code/descripex` | `descripex` | 0.11.0 | Discovery/`describe` protocol — gates the whole stack via version bounds | — |
| zen_websocket | `~/_DATA/code/zen_websocket` | `zen_websocket` | 0.4.2 | WebSocket client substrate (feeds `onchain`) | — |

**Onchain family** (the connected cascade):

| Repo | Path | Hex package | Local ver | Role | Native |
|---|---|---|---|---|---|
| hieroglyph | `~/_DATA/code/hieroglyph` | `hieroglyph` | 1.5.0 | ABI encode/decode (`ABI.*`) | yecc/leex |
| cartouche | `~/_DATA/code/cartouche` | `cartouche` | 0.3.0 | Substrate: signing, tx encoding, raw RPC, crypto | — |
| onchain | `~/_DATA/code/onchain` | `onchain` | 0.8.0 | Core primitives: RPC, ABI, ERC, signing | — |
| onchain_aave | `~/_DATA/code/onchain_aave` | `onchain_aave` | 0.2.0 | Aave V3 wrappers | — |
| onchain_evm | `~/_DATA/code/onchain_evm` | `onchain_evm` | 0.2.0 | EVM sim, Solidity parse, trace, codegen | Rust (Rustler) |
| onchain_js | `~/_DATA/code/onchain_js` | `onchain_js` | 0.2.0 | npm packages on the BEAM (QuickBEAM) | Zig NIFs |
| onchain_tempo | `~/_DATA/code/onchain_tempo` | `onchain_tempo` | 0.3.0 | Tempo chain primitives (0x76 tx, TIP-20) | — |
| mpp | `~/_DATA/code/mpp` | `mpp` | 0.5.1 | Top-level consumer/app | Phoenix |

> Local versions are a **dated snapshot (2026-06-19)** — they drift. Treat them as
> a starting hint, never ground truth. Always re-read each repo's `mix.exs` and
> run `mix hex.info <pkg>` before acting (Operating Rules).
>
> **Scope note:** the home stays scoped to *this* dependency cascade. Don't fold in
> the rest of zenhive — the value here is one coherent dep graph with a defined
> publish order; unrelated packages have no cascade story and would turn this doc
> into a flat list. A generic all-packages publish dashboard, if ever wanted, is a
> separate (config-driven) tool, not this cascade-narrative home.

---

## Dependency graph

```
descripex ─┐                         (shared upstream)
           ↓
       hieroglyph ──→ cartouche ──→ onchain ──┬──→ onchain_aave
                                       ↑       ├──→ onchain_evm
                       zen_websocket ──┘       ├──→ onchain_js
                          (shared upstream)    └──→ onchain_tempo ──→ mpp
```

Edges as of the snapshot (verify in each `mix.exs`):

- hieroglyph → `descripex ~> 0.6`
- cartouche → `hieroglyph ~> 1.5`, `descripex ~> 0.11` *(local; Hex still 0.9.1 — see below)*
- onchain → `cartouche ~> 0.3`, `descripex ~> 0.9`, `zen_websocket ~> 0.4.2`
- onchain_aave / onchain_evm / onchain_js / onchain_tempo → `onchain ~> 0.8`, `descripex ~> 0.9`
- mpp → `onchain ~> 0.8`, `onchain_tempo ~> 0.3`, `descripex ~> 0.9`
- onchain_aave → `{:onchain_evm, path: "../onchain_evm", only: [:dev, :test]}` (sibling path dep — **another reason repos must not move**)

`descripex` and `zen_websocket` are roots — no first-party upstream of their own —
so a release there starts the whole cascade. Because they're consumed beyond this
family, bump them deliberately and note the wider blast radius.

---

## Release cascade rule

**Upstream-first, one published version at a time.** A change at any node ripples
*down* the graph. Publish the upstream, then `mix deps.update` and re-test each
dependent before publishing it. Never publish a dependent against an unpublished
upstream version.

Canonical order when the whole stack moves:

```
descripex ─┐
zen_websocket ─┴→ hieroglyph → cartouche → onchain → {onchain_aave, onchain_evm, onchain_js, onchain_tempo} → mpp
```

(`zen_websocket` feeds `onchain` directly, not hieroglyph — it just shares the
"publish the upstream before the dependent" rule.) The four mid-tier siblings
(aave/evm/js/tempo) are mutually independent — once `onchain` ships they can publish
in any order. `mpp` is always last (it consumes the tier above).

---

## Current cascade state (2026-06-19)

Two live items:

**1. onchain_evm 0.2.0 is publish-ready but unpublished.** Hex still has `0.1.0`
(2026-03-27). Local `0.2.0` is green (offline + integration), CHANGELOG/README/
SKILL.md updated, Task 49 fixed. Independent of the descripex cascade — can ship
now on `descripex ~> 0.9`.

**2. The descripex 0.11 unblock (worked example of the cascade).**
- `descripex 0.11.0` is on Hex.
- **cartouche local** `mix.exs` already declares `descripex ~> 0.11`, but **Hex
  cartouche 0.3.0 still declares `descripex ~> 0.9.1`** (= `>= 0.9.1, < 0.10.0`),
  which hard-caps descripex below 0.10 for everything that pulls cartouche.
- So the local cartouche is **ahead of Hex, unpublished** — that is the *only*
  real blocker. onchain and all downstream already declare `descripex ~> 0.9`
  (which permits 0.11), so they need no bound change, only a `deps.update` +
  republish once cartouche ships.

Unblock sequence: **cartouche** (bump version, publish — carries `descripex ~> 0.11`)
→ **onchain** (`mix deps.update descripex cartouche`, bump, publish) → downstream
`deps.update` + republish as needed.

---

## Publish workflow (per repo)

**Tooling:** `./bin/publish-prep.sh status` shows every repo's local-vs-Hex
version delta; `./bin/publish-prep.sh check <repo> [--integration]` runs the
deterministic gauntlet (clean tree → version delta → deps.get → hex.audit →
compile -Werror → tests → CHANGELOG → `hex.build` dry-run) and prints the exact
publish command. The script **never publishes** — `mix hex.publish` (2FA) is yours.

You prepare; the **human runs `mix hex.publish`** (2FA). For each repo being released:

1. `cd ~/_DATA/code/<repo>` — work happens in the repo; this home only coordinates.
2. `git fetch && git status` — clean tree; note local-vs-Hex version delta.
3. `mix deps.update <changed-upstreams>` — pull the freshly published upstream.
4. Compile + full suite (incl. integration where the repo has it). Green is the gate.
5. Bump `@version` / `version:` per semver against the **published** baseline.
6. Update `CHANGELOG.md` (and README/SKILL.md if surface changed).
7. Commit path-scoped, push.
8. **Hand off to the human:** state the exact `mix hex.publish` command and that
   2FA is required. Do **not** run it yourself.

After the human confirms the publish, `mix hex.info <pkg>` should show the new
version before you start the next downstream repo.

---

## Operating rules

- **Verify live; the local tree can be ahead of Hex.** cartouche is the proof:
  local `mix.exs` deps ≠ published deps at the same version number. Before any
  cascade decision, read the repo's `mix.exs` *and* `mix hex.info <pkg>` /
  `mix hex.outdated` — never trust the snapshot table above.
- **Repos do not move.** Location is irrelevant under Hex, and `onchain_aave`'s
  `../onchain_evm` path dep would break. This home references them by absolute path.
- **Per-repo CLAUDE.md wins inside its repo.** Those carry the toolchain, test
  commands (`mix test.json`), coverage tiers, and hook rules. This home governs
  only cross-repo ordering and publish-prep.
- **Stage path-scoped.** Never `git add -A` / `git commit -a` — the family repos
  may have parallel WIP. Stage explicit paths; verify `git diff --cached --name-only`.
- **No Co-Authored-By footers.** Title-only commit messages (`<scope>: <desc>`).
- **Publish is human-gated (2FA).** Always. Your terminal state is *publish-ready*.
- **Local cross-stack dev without Hex round-trips:** for active multi-repo work,
  a dev/test-only path dep (`{:dep, path: "../dep", only: [:dev, :test]}`, as
  onchain_aave already uses for onchain_evm) lets you build against local
  checkouts. Release/CI still resolves the pinned Hex version. Use it to avoid
  publishing just to test a downstream — but the *published* `mix.exs` must pin
  the Hex version, never a path.

---

## AGENTS.md

`AGENTS.md` (for Codex/Cursor/Grok, which don't read Claude includes/hooks) is
generated from this file. This `CLAUDE.md` is self-contained (no `@`-imports), so
the render is effectively 1:1. Regenerate after every edit:

```bash
cd ~/_DATA/code/onchain-stack
~/_DATA/code/claude-marketplace/scripts/sync-agents-md.sh          # write AGENTS.md
~/_DATA/code/claude-marketplace/scripts/sync-agents-md.sh --check  # CI freshness gate
```
