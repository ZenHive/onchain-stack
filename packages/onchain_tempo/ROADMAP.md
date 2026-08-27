# OnchainTempo Roadmap

**Vision:** Standalone Tempo blockchain primitives for the Elixir ecosystem.

**Completed work:** See [CHANGELOG.md](CHANGELOG.md) for finished tasks.

---

## Phase 1: Extraction from MPP

> Initial extraction of Tempo primitives from MPP into standalone library.
> Built: TIP20, Transaction (deserialize + build + sign + fee payer), RPC, Transfer.

<!-- TASKS:BEGIN phase=1 -->
> 1 task. See [CHANGELOG.md](CHANGELOG.md#phase-1-extraction-from-mpp).
<!-- TASKS:END -->

---

## Phase 2: Hex Release & Integration Coverage

<!-- TASKS:BEGIN phase=2 -->
> 6 tasks. See [CHANGELOG.md](CHANGELOG.md#phase-2-hex-release-integration-coverage).
<!-- TASKS:END -->

---

## Phase 3: Future Work

<!-- TASKS:BEGIN phase=3 -->
| Task | Status | Notes |
|------|--------|-------|
| Task 6 | ✅ | 🎁 **faucet_polish** · Replace Faucet fixed-sleep settle with poll loop [D:3/B:3/U:3 → Eff:1.0?] 📋 |
| Task 7 | ✅ | 🎁 **public_faucet** · Public `Onchain.Tempo.Faucet` helper for `tempo_fundAddress` [D:2/B:5/U:5 → Eff:2.5?] 🎯 |
| Task 10 | ✅ | 🎁 **integration_coverage** · Stop hardcoding Builder @default_gas_limit — estimate gas per-tx (mirror mppx) [D:3/B:4/U:6 → Eff:1.67?] 🚀 |
| Task 11 | ✅ | 🎁 **cartouche_migration** · Update transport stub off the :cartouche,:client seam after onchain's Req migration [D:2/B:5/U:5 → Eff:2.5?] 🎯 |
| Task 12 | ✅ | 🎁 **verification** · 🔒 Mutation-grade 0x76 transaction and signing invariants [D:5/B:9/U:8 → Eff:1.7] 🚀 |
| Task 13 | ⬜ | 🎁 **verification** · 🔒 Verify optional 0x76 key_authorization across encode, sign, and recover [D:5/B:7/U:4 → Eff:1.1] 📋 |
<!-- TASKS:END -->
