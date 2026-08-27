# ABI Roadmap

**Vision:** Production-grade Solidity ABI encoder/decoder for Elixir, matching feature parity with `eth-abi` (Python), `ethers`/`viem` (JS), and `alloy` (Rust).

> This file is **rendered by `rmap`** from `roadmap/tasks.toml`. Edit tasks via `rmap` (or `tasks.toml`) and run `rmap render` — do not hand-edit the task tables between the `<!-- TASKS:* -->` markers. Prose outside the markers is preserved.

**Completed work:** see [CHANGELOG.md](CHANGELOG.md). The bulk of this roadmap (Phases 1–4) shipped across 1.0.0–1.4.0; the per-task record lives in `tasks.toml` (`rmap list --status done`). The live work is **Phase 5 — Peer-Library Parity**.

**Task completion rule:** a task is not done until its docs land. At minimum every task produces a CHANGELOG entry under `## [Unreleased]`; user-facing surface changes also update README; architectural/convention changes also update CLAUDE.md.

<!-- FOCUS:BEGIN -->
**Focus phase:** 5 — Peer-Library Parity (13 of 15 done · 1 in progress)

**Last shipped:** Task 44 — Independent-oracle + planted-mutant verification for the ABI wire format, Task 45 — Gate api_manifest.json freshness in mix ci on 2026-08-22

**Up next:** none — focus phase complete or all blocked
<!-- FOCUS:END -->

---

## Phase 1 — Upstream & Fork Bug Fixes

<!-- TASKS:BEGIN phase=1 -->
> 6 tasks. See [CHANGELOG.md](CHANGELOG.md#phase-1-upstream-fork-bug-fixes).
<!-- TASKS:END -->

## Phase 2 — Agent Economy (Descripex)

<!-- TASKS:BEGIN phase=2 -->
> 3 tasks. See [CHANGELOG.md](CHANGELOG.md#phase-2-agent-economy-descripex).
<!-- TASKS:END -->

## Phase 3 — Public Surface & Quality Debt

<!-- TASKS:BEGIN phase=3 -->
> 15 tasks. See [CHANGELOG.md](CHANGELOG.md#phase-3-public-surface-quality-debt).
<!-- TASKS:END -->

## Phase 4 — DeFi Fixtures & Property Suite

<!-- TASKS:BEGIN phase=4 -->
> 7 tasks. See [CHANGELOG.md](CHANGELOG.md#phase-4-defi-fixtures-property-suite).
<!-- TASKS:END -->

## Phase 5 — Peer-Library Parity

The encode-side symmetry trio (`encode_call/3`, `encode_error/3`, `encode_event_topics/2`) ships as one minor bump under the **Encode-Side Symmetry** milestone; the three standalone items (`get_abi_item/3`, strict-decode, deferred `fixed`/`ufixed`) ship independently.

<!-- TASKS:BEGIN phase=5 -->
| Task | Status | Notes |
|------|--------|-------|
| Task 32 | ✅ | 🎁 **peer_parity** · ABI.decode_call/3 + ABI.method_id/1 [D:2/B:5/U:6 → Eff:2.75?] 🎯 |
| Task 33 | ✅ | 🎁 **peer_parity** · Implement function type encode/decode [D:2/B:5/U:5 → Eff:2.5?] 🎯 |
| Task 34 | ✅ | 🎁 **encode_symmetry** · 🚀 **encode_symmetry** · ABI.encode_call/3 (selector-prefixed calldata) [D:2/B:5/U:6 → Eff:2.75?] 🎯 |
| Task 35 | ✅ | 🎁 **encode_symmetry** · 🚀 **encode_symmetry** · ABI.encode_error/3 (Solidity 0.8.4+ custom-error revert blob) [D:2/B:5/U:4 → Eff:2.25?] 🎯 |
| Task 36 | ✅ | 🎁 **encode_symmetry** · 🚀 **encode_symmetry** · ABI.encode_event_topics/2 (event log topic filter builder) [D:4/B:7/U:7 → Eff:1.75?] 🚀 |
| Task 37 | ✅ | 🎁 **peer_parity** · ABI.get_abi_item/3 (lookup helper over parse_specification output) [D:2/B:3/U:3 → Eff:1.5?] 🚀 |
| Task 38 | ✅ | 🎁 **peer_parity** · Strict-decode mode (strict: true opt) [D:5/B:6/U:4 → Eff:1.0?] 📋 |
| Task 39 | 🔶 | 🎁 **peer_parity** · Implement fixed<M>x<N> / ufixed<M>x<N> [D:8/B:3/U:2 → Eff:0.31?] ⚠️ ⛔ External: Solidity itself does not support fixed-point (declarable, not assignable), so there is no real-world corpus to encode against. Parse-time rejection + README rationale already ship (task 2, 1.0.0). Unblock condition: Solidity lands assignable fixed<M>x<N>, or a downstream consumer surfaces a concrete need. |
| Task 40 | ✅ | 🎁 **peer_parity** · Built-in Error(string) / Panic(uint256) auto-decoding in decode_error/2 [D:2/B:7/U:7 → Eff:3.5?] 🎯 |
| Task 41 | ✅ | 🎁 **peer_parity** · ABI.encode_constructor/2 (deploy-time argument encoding) [D:3/B:5/U:5 → Eff:1.67?] 🚀 |
| Task 42 | ✅ | 🎁 **peer_parity** · ABI.format_abi_item/1 (FunctionSelector -> canonical signature string) [D:3/B:3/U:4 → Eff:1.17?] 📋 |
| Task 43 | ✅ | 🎁 **agent_economy** · SKILL.md for AI-agent consumers of the ABI library [D:3/B:6/U:6 → Eff:2.0?] 🎯 |
| Task 44 | ✅ | 🎁 **peer_parity** · 🔒 Independent-oracle + planted-mutant verification for the ABI wire format [D:5/B:8/U:6 → Eff:1.4] 📋 |
| Task 45 `[CX]` | ✅ | 🎁 **agent_economy** · Gate api_manifest.json freshness in mix ci [D:2/B:6/U:5 → Eff:2.75] 🎯 |
| Task 46 | 🔄 | 🎁 **peer_parity** · 🔒 muex sweep over the ABI surface, graded against the task 44 planted-mutant corpus [D:4/B:6/U:3 → Eff:1.12] 📋 |
<!-- TASKS:END -->

---

## Upstream / Fork Split

Upstream (`exthereum/abi`) is dormant and no longer tracked — issues #53/#54/#55 and PR #52 sit unanswered, and no further filings are planned. Fixes ship here. See CLAUDE.md § "Upstream Divergence" for the map of where this fork diverges and why (reference, not a work queue).
