# Onchain Stack Roadmap

**Vision:** Monorepo of the eight-package EVM cascade — hieroglyph, cartouche, onchain and the five consumers (aave, aerodrome, evm, js, tempo). One repository, verified at HEAD in a single mix ci through path deps; eight unchanged Hex packages published outward. Task ids carry their package's thousand-range (hieroglyph 1xxx … onchain_tempo 8xxx) and target_repo names the package a task lands in.

**Canonical source:** `roadmap/tasks.toml` — this file is rendered by `rmap render`. Do not hand-edit inside the marker pairs.

**Task id ranges carry provenance:** hieroglyph 1xxx · cartouche 2xxx · onchain 3xxx · onchain_aave 4xxx · onchain_aerodrome 5xxx · onchain_evm 6xxx · onchain_js 7xxx · onchain_tempo 8xxx. Every task also carries `target_repo = "<package>"`.

**Completed work:** see each package's `packages/<name>/CHANGELOG.md`.

---

## Milestones

<!-- MILESTONES:BEGIN -->
### hieroglyph_encode_symmetry — [hieroglyph] Encode-Side Symmetry

- **target_version:** 1.5.0
- **status:** 🔄 active
- **hypothesis:** Proves consumers building transactions need the encode-side counterparts (encode_call / encode_error / encode_event_topics) to match the decode APIs already shipped, rather than hand-assembling selector-prefixed calldata.
- **pinned tasks:** 3/3 done

### onchain_aave_v0_5 — [onchain_aave] Live-evidenced V3/V4 surface

- **target_version:** 0.5.0
- **status:** 🔄 active
- **hypothesis:** Tests whether onchain_aave can express core V3 position-management and V4 Hub-and-Spoke flows with reproducible evidence against deployed Aave contracts.
- **pinned tasks:** 1/5 done

### onchain_aerodrome_v0_1 — [onchain_aerodrome] Full read surface, analytics and prices

- **target_version:** 0.1.0
- **status:** 🔄 active
- **hypothesis:** Tests whether the complete Aerodrome read surface — Sugar reads, a built-in price layer, and denominator-tagged analytics — can ship with correctness graded by deployed contracts rather than by our own code, given that Base EVM simulation is structurally blocked.
- **pinned tasks:** 0/27 done

### onchain_js_v0_3 — [onchain_js] First real npm library end-to-end

- **target_version:** 0.3.0
- **status:** 🔄 active
- **hypothesis:** Proves an npm Ethereum library can be installed, loaded and driven from Elixir through QuickBEAM with no Node.js on the host — solc-js is the first consumer that has to work for real.
- **pinned tasks:** 0/2 done

### onchain_aerodrome_v0_2 — [onchain_aerodrome] Write surface without simulation

- **target_version:** 0.2.0
- **status:** ⬜ pending
- **hypothesis:** Tests whether a full Router/Gauge/NFPM/Voter write surface can ship with honest evidence when no local EVM can execute it — calldata graded against an independent encoder and real on-chain reverts, never against our own encoder.
- **pinned tasks:** 0/8 done

### onchain_js_v0_4 — [onchain_js] The JS library shelf

- **target_version:** 0.4.0
- **status:** ⬜ pending
- **hypothesis:** Proves the bridge generalizes past one library — that unmodified DeFi SDKs (Uniswap, DeFiSaver, 1inch) and utility libraries (aave math-utils, merkletreejs) run on the BEAM through the same loading contract solc-js proved out.
- **pinned tasks:** 0/5 done
<!-- MILESTONES:END -->

---

## hieroglyph

### Phase 1001: Upstream & Fork Bug Fixes

<!-- TASKS:BEGIN phase=1001 -->
> 6 tasks. See [CHANGELOG.md](CHANGELOG.md#phase-1001-hieroglyph-upstream-fork-bug-fixes).
<!-- TASKS:END -->

### Phase 1002: Agent Economy (Descripex)

<!-- TASKS:BEGIN phase=1002 -->
> 3 tasks. See [CHANGELOG.md](CHANGELOG.md#phase-1002-hieroglyph-agent-economy-descripex).
<!-- TASKS:END -->

### Phase 1003: Public Surface & Quality Debt

<!-- TASKS:BEGIN phase=1003 -->
> 15 tasks. See [CHANGELOG.md](CHANGELOG.md#phase-1003-hieroglyph-public-surface-quality-debt).
<!-- TASKS:END -->

### Phase 1004: DeFi Fixtures & Property Suite

<!-- TASKS:BEGIN phase=1004 -->
> 7 tasks. See [CHANGELOG.md](CHANGELOG.md#phase-1004-hieroglyph-defi-fixtures-property-suite).
<!-- TASKS:END -->

### Phase 1005: Peer-Library Parity

<!-- TASKS:BEGIN phase=1005 -->
| Task | Status | Notes |
|------|--------|-------|
| Task 1032 | ✅ | 🎁 **hieroglyph_peer_parity** · ABI.decode_call/3 + ABI.method_id/1 [D:2/B:5/U:6 → Eff:2.75?] 🎯 |
| Task 1033 | ✅ | 🎁 **hieroglyph_peer_parity** · Implement function type encode/decode [D:2/B:5/U:5 → Eff:2.5?] 🎯 |
| Task 1034 | ✅ | 🎁 **hieroglyph_encode_symmetry** · 🚀 **hieroglyph_encode_symmetry** · ABI.encode_call/3 (selector-prefixed calldata) [D:2/B:5/U:6 → Eff:2.75?] 🎯 |
| Task 1035 | ✅ | 🎁 **hieroglyph_encode_symmetry** · 🚀 **hieroglyph_encode_symmetry** · ABI.encode_error/3 (Solidity 0.8.4+ custom-error revert blob) [D:2/B:5/U:4 → Eff:2.25?] 🎯 |
| Task 1036 | ✅ | 🎁 **hieroglyph_encode_symmetry** · 🚀 **hieroglyph_encode_symmetry** · ABI.encode_event_topics/2 (event log topic filter builder) [D:4/B:7/U:7 → Eff:1.75?] 🚀 |
| Task 1037 | ✅ | 🎁 **hieroglyph_peer_parity** · ABI.get_abi_item/3 (lookup helper over parse_specification output) [D:2/B:3/U:3 → Eff:1.5?] 🚀 |
| Task 1038 | ✅ | 🎁 **hieroglyph_peer_parity** · Strict-decode mode (strict: true opt) [D:5/B:6/U:4 → Eff:1.0?] 📋 |
| Task 1039 | 🔶 | 🎁 **hieroglyph_peer_parity** · Implement fixed<M>x<N> / ufixed<M>x<N> [D:8/B:3/U:2 → Eff:0.31?] ⚠️ ⛔ External: Solidity itself does not support fixed-point (declarable, not assignable), so there is no real-world corpus to encode against. Parse-time rejection + README rationale already ship (task 2, 1.0.0). Unblock condition: Solidity lands assignable fixed<M>x<N>, or a downstream consumer surfaces a concrete need. |
| Task 1040 | ✅ | 🎁 **hieroglyph_peer_parity** · Built-in Error(string) / Panic(uint256) auto-decoding in decode_error/2 [D:2/B:7/U:7 → Eff:3.5?] 🎯 |
| Task 1041 | ✅ | 🎁 **hieroglyph_peer_parity** · ABI.encode_constructor/2 (deploy-time argument encoding) [D:3/B:5/U:5 → Eff:1.67?] 🚀 |
| Task 1042 | ✅ | 🎁 **hieroglyph_peer_parity** · ABI.format_abi_item/1 (FunctionSelector -> canonical signature string) [D:3/B:3/U:4 → Eff:1.17?] 📋 |
| Task 1043 | ✅ | 🎁 **hieroglyph_agent_economy** · SKILL.md for AI-agent consumers of the ABI library [D:3/B:6/U:6 → Eff:2.0?] 🎯 |
| Task 1044 | ✅ | 🎁 **hieroglyph_peer_parity** · 🔒 Independent-oracle + planted-mutant verification for the ABI wire format [D:5/B:8/U:6 → Eff:1.4] 📋 |
| Task 1045 `[CX]` | ✅ | 🎁 **hieroglyph_agent_economy** · Gate api_manifest.json freshness in mix ci [D:2/B:6/U:5 → Eff:2.75] 🎯 |
| Task 1046 | 🔄 | 🎁 **hieroglyph_peer_parity** · 🔒 muex sweep over the ABI surface, graded against the task 44 planted-mutant corpus [D:4/B:6/U:3 → Eff:1.12] 📋 |
<!-- TASKS:END -->

---

## cartouche

### Phase 2000: Ship 0.1.0 + pre/post-release hardening

<!-- TASKS:BEGIN phase=2000 -->
| Task | Status | Notes |
|------|--------|-------|
| Task 2001 | ✅ | 🎁 **cartouche_release_010** · Reset mix.exs version 1.6.1 → 0.1.0-dev [D:1/B:3/U:7 → Eff:5.0?] 🎯 |
| Task 2002 | ✅ | 🎁 **cartouche_release_010** · Full mix test.json --quiet pass on the ported code [D:3/B:5/U:7 → Eff:2.0?] 🎯 |
| Task 2003 | ✅ | 🎁 **cartouche_release_010** · mix dialyzer.json --quiet — inventory remaining invalid_contract warnings, confirm they match the pre-rename audit [D:2/B:3/U:6 → Eff:2.25?] 🎯 |
| Task 2004 | ✅ | 🎁 **cartouche_release_010** · mix docs clean build with cartouche branding intact [D:2/B:3/U:5 → Eff:2.0?] 🎯 |
| Task 2005 | ✅ | 🎁 **cartouche_release_010** · Update README.md installation section — replace the 'not recommended yet' placeholder with real install instructions [D:1/B:3/U:7 → Eff:5.0?] 🎯 |
| Task 2006 | ✅ | 🎁 **cartouche_release_010** · Tag 0.1.0, publish to hex [D:1/B:5/U:8 → Eff:6.5?] 🎯 |
| Task 2036 | ✅ | 🎁 **cartouche_release_010** · Silence ex_doc 'documentation references type X but the module is hidden' warnings surfaced by mix docs [D:2/B:2/U:4 → Eff:1.5?] 🚀 |
| Task 2037 | ✅ | 🎁 **cartouche_release_010** · Publish cut — version bump, CHANGELOG release section, mix.exs :package polish, README install activation [D:1/B:3/U:5 → Eff:4.0?] 🎯 |
| Task 2040 | ✅ | 🎁 **cartouche_generator_hardening** · Generator (lib/mix/cartouche.gen.ex) credo cleanup [D:5/B:2/U:3 → Eff:0.5?] ⚠️ |
| Task 2038 | ✅ | 🎁 **cartouche_release_010** · Delete Cartouche.Util grab-bag — redistribute helpers into focused modules, drop @deprecated aliases [D:3/B:3/U:5 → Eff:1.33?] 📋 |
| Task 2051 | ✅ | 🎁 **cartouche_correctness_010** · Cartouche.Trace.t().trace_address typed singular but runtime is a list [D:1/B:5/U:7 → Eff:6.0?] 🎯 |
| Task 2052 | ✅ | 🎁 **cartouche_correctness_010** · Cartouche.TraceCall.t().trace typed singular but runtime is a list [D:1/B:5/U:7 → Eff:6.0?] 🎯 |
| Task 2053 | ✅ | 🎁 **cartouche_correctness_010** · V1.t() Schrödinger r/s/v + latent decode → recover_signer crash [D:4/B:7/U:6 → Eff:1.62?] 🚀 |
| Task 2056 | ✅ | 🎁 **cartouche_correctness_010** · Harden Cartouche.Solana.Transaction.deserialize/1 crash paths [D:2/B:6/U:6 → Eff:3.0?] 🎯 |
| Task 2041 `[CX]` | ✅ | 🎁 **cartouche_generator_hardening** · Generator bytecode-flag separation — init vs deployed [D:3/B:2/U:3 → Eff:0.83?] ⚠️ |
| Task 2042 | ✅ | 🎁 **cartouche_generator_hardening** · Generator decode_error/1 template — drop dead if true ... else ... end branch [D:1/B:1/U:2 → Eff:1.5?] 🚀 |
| Task 2044 `[CSR]` | ✅ | 🎁 **cartouche_generator_hardening** · Generator coverage push — raise Mix.Tasks.Cartouche.Gen to ≥80% before Tasks 41 + 42 [D:3/B:4/U:6 → Eff:1.67?] 🚀 |
| Task 2047 | ✅ | 🎁 **cartouche_generator_hardening** · Exclude generated Cartouche.Contract.IConsole from coverage measurement [D:1/B:1/U:3 → Eff:2.0?] 🎯 |
| Task 2049 | ⛔ | 🎁 **cartouche_generator_hardening** · Resolve Cartouche.Transaction.V2.encode/1 spec duplication — superseded by Task 54 [D:1/B:1/U:1 → Eff:1.0?] 📋 |
| Task 2054 `[CSR]` | ✅ | 🎁 **cartouche_generator_hardening** · Extract Cartouche.Transaction.Call — collapse the V2-as-eth-call-shape lie [D:6/B:5/U:5 → Eff:0.83?] ⚠️ |
| Task 2050 `[CX]` | ✅ | 🎁 **cartouche_generator_hardening** · Generator emits @doc/@spec on generated bindings — drop .doctor.exs ignore_paths [D:3/B:2/U:3 → Eff:0.83?] ⚠️ |
| Task 2048 `[CSR]` | ✅ | 🎁 **cartouche_sleuth_hardening** · Harden Cartouche.Sleuth atom-table risks [D:5/B:4/U:5 → Eff:0.9?] ⚠️ |
| Task 2055 | ✅ | 🎁 **cartouche_trace_hardening** · Harden Cartouche.Trace.deserialize/1 against missing/nil traceAddress [D:1/B:2/U:3 → Eff:2.5?] 🎯 |
| Task 2043 | ✅ | 🎁 **cartouche_coverage_pushes** · Pre-credo coverage push for cleanup-target modules [D:3/B:5/U:7 → Eff:2.0?] 🎯 |
| Task 2057 | ✅ | 🎁 **cartouche_solana_hardening** · Fix Cartouche.Solana.Transaction.sign_partial/2 zero-signer boundary [D:1/B:3/U:3 → Eff:3.0?] 🎯 |
| Task 2058 `[CX]` | ✅ | 🎁 **cartouche_rpc_correctness** · Strengthen Cartouche.Filter expired-filter test — assert recovery-branch fingerprint [D:1/B:2/U:2 → Eff:2.0?] 🎯 |
| Task 2059 `[CSR]` | ✅ | 🎁 **cartouche_generator_hardening** · Reach 1.8 → 2.2 bump + hygiene pass [D:1/B:2/U:1 → Eff:1.5?] 🚀 |
| Task 2060 | ✅ | 🎁 **cartouche_rpc_correctness** · Cartouche.RPC.get_block_by_number/2 integer path crashes on real nodes [D:1/B:3/U:4 → Eff:3.5?] 🎯 |
| Task 2061 | ✅ | 🎁 **cartouche_rpc_correctness** · Mainnet archive integration test suite — read-only RPC sweep [D:3/B:6/U:7 → Eff:2.17?] 🎯 |
| Task 2062 | ✅ | 🎁 **cartouche_rpc_correctness** · v2 traces — integration anchors for trace_transaction, trace_call, trace_callMany, debug_traceCall [D:5/B:5/U:5 → Eff:1.0?] 📋 |
| Task 2063 | ✅ | 🎁 **cartouche_block_fork_fields** · Cartouche.Block — add base_fee_per_gas (London+) [D:1/B:3/U:5 → Eff:4.0?] 🎯 |
| Task 2064 | ✅ | 🎁 **cartouche_block_fork_fields** · Cartouche.Block — add withdrawals_root and withdrawals (Shanghai+) [D:2/B:3/U:5 → Eff:2.0?] 🎯 |
| Task 2065 | ✅ | 🎁 **cartouche_block_fork_fields** · Cartouche.Block — add Cancun fields (parent_beacon_block_root, blob_gas_used, excess_blob_gas, mix_hash) [D:2/B:3/U:5 → Eff:2.0?] 🎯 |
| Task 2066 `[CSR]` | ✅ | 🎁 **cartouche_rpc_correctness** · Cartouche.Block.transactions — implement include_transaction_details: true [D:5/B:4/U:5 → Eff:0.9?] ⚠️ |
| Task 2099 | ✅ | 🎁 **cartouche_rpc_correctness** · Cartouche.Transaction.V_2930 — add EIP-2930 (type 0x1) JSON deserialization [D:3/B:2/U:2 → Eff:0.67?] ⚠️ |
| Task 2067 | ✅ | 🎁 **cartouche_rpc_correctness** · Cartouche.Receipt — add EIP-4844 blob fields (blob_gas_used, blob_gas_price) [D:2/B:3/U:4 → Eff:1.75?] 🚀 |
| Task 2068 | ⛔ | 🎁 **cartouche_eip_opcode_followups** · Cartouche.DebugTrace.StructLog — add EIP-7702 opcodes to the closed whitelist (AUTH, AUTHCALL) — closed obsolete [D:1/B:1/U:1 → Eff:1.0?] 📋 |
| Task 2069 | ✅ | 🎁 **cartouche_bug_triage** · Audit RPC-level requirements bubbling up from defi-skills mining [D:2/B:5/U:4 → Eff:2.25?] 🎯 |
| Task 2070 `[CX]` | ✅ | 🎁 **cartouche_eip_opcode_followups** · Cartouche.DebugTrace.StructLog — add CLZ (EIP-7939/Osaka) to the closed whitelist [D:1/B:2/U:3 → Eff:2.5?] 🎯 |
| Task 2073 | ✅ | 🎁 **cartouche_kms_followups** · KMS signer Goth-path test mocking — clear critical-tier ≥95% gate on both KMS signers [D:3/B:2/U:3 → Eff:0.83?] ⚠️ |
| Task 2075 `[CX]` | ✅ | 🎁 **cartouche_tooling_quality** · Backfill @spec on every defp to enable .credo.exs {Specs, [include_defp: true]} portfolio-wide [D:7/B:5/U:5 → Eff:0.71?] ⚠️ |
| Task 2076 | ✅ | 🎁 **cartouche_tooling_quality** · Restore dialyzer to the standard PR harness — the OOM premise was the Assembly bomb, now fixed [D:3/B:2/U:3 → Eff:0.83?] ⚠️ |
| Task 2074 | ✅ | 🎁 **cartouche_wei_units** · Cartouche.Wei.to_wei/1 — add :eth denomination with Decimal support [D:3/B:3/U:3 → Eff:1.0?] 📋 |
| Task 2077 `[CSR]` | ✅ | 🎁 **cartouche_coverage_pushes** · Cartouche.Solana.RPC coverage push — pre-existing untested option/filter/encoding paths [D:2/B:3/U:4 → Eff:1.75?] 🚀 |
| Task 2091 `[CX]` | ✅ | 🎁 **cartouche_solana_hardening** · Cartouche.Solana.Transaction.sign/2 — reject signer-count mismatch against message.header.num_required_signatures [D:1/B:3/U:3 → Eff:3.0?] 🎯 |
| Task 2092 `[CX]` | ✅ | 🎁 **cartouche_solana_hardening** · Cartouche.Solana.Transaction.add_signature/3 — guard index against length(transaction.signatures) before List.replace_at/3 [D:1/B:3/U:3 → Eff:3.0?] 🎯 |
| Task 2103 | ✅ | 🎁 **cartouche_generator_hardening** · Fix the ~30 GB downstream dialyzer bomb — collapse Assembly.compile/1's 7-arity tuple_set (NOT IConsole) [D:4/B:7/U:6 → Eff:1.62?] 🚀 |
| Task 2105 | ⬜ | 🎁 **cartouche_generator_hardening** · Optional: slim generated IConsole surface (~250 MB dialyzer win, not the bomb) [D:3/B:2/U:3 → Eff:0.83?] ⚠️ |
| Task 2104 | ✅ | 🎁 **cartouche_signer_backends** · Formalize signer backends as a behaviour (pure digest-signer contract) — unlock multi-provider signing [D:4/B:6/U:6 → Eff:1.5?] 🚀 |
| Task 2106 | ✅ | 🎁 **cartouche_generator_hardening** · Generator fixture: unlinked-library / immutable bytecode placeholders through blank_bytecode?/hex! [D:2/B:3/U:3 → Eff:1.5?] 🚀 |
| Task 2109 | ✅ | 🎁 **cartouche_tooling_quality** · Finish + normalize typed-transaction helper extraction (dedup maybe_to_wei/chain_id_value; migrate V3 onto TypedDecode/Signature) [D:2/B:4/U:4 → Eff:2.0?] 🎯 |
| Task 2110 | ✅ | 🎁 **cartouche_tooling_quality** · defrpc macro — generate uniform JSON-RPC wrappers + @spec + @doc + Descripex api() from one declaration [D:5/B:6/U:5 → Eff:1.1?] 📋 |
| Task 2111 | ⛔ | 🎁 **cartouche_tooling_quality** · Spike: evaluate a Cartouche.Transaction.Typed envelope macro across V_2930/V3/V4 [D:2/B:3/U:3 → Eff:1.5?] 🚀 |
| Task 2113 | ✅ | 🎁 **cartouche_coverage_pushes** · 🔒 Property + cross-implementation vector suite for Ethereum tx envelopes and signing [D:4/B:8/U:8 → Eff:2.0] 🎯 |
| Task 2114 | ✅ | 🎁 **cartouche_coverage_pushes** · 🔒 Mutation-adequacy campaign over the signing and transaction paths [D:5/B:7/U:6 → Eff:1.3] 📋 |
| Task 2115 | ✅ | 🎁 **cartouche_phase8_dedup** · Cartouche.Transaction.V_2930 write surface — new/encode/sign/hash/signature/recover [D:3/B:4/U:4 → Eff:1.33] 📋 |
| Task 2116 | ✅ | 🎁 **cartouche_signer_backends** · 🔒 Enforce the Signer.Backend contract at the boundary — payload length, curve, DER parse [D:3/B:6/U:6 → Eff:2.0] 🎯 |
| Task 2117 | ✅ | 🎁 **cartouche_phase9_tx** · 🔒 Encode must not emit wire-non-conformant RLP — close the encode/decode conformance gap across V2/V3/V4 [D:3/B:8/U:7 → Eff:2.5] 🎯 |
| Task 2118 | ✅ | 🎁 **cartouche_signer_backends** · 🔒 Low-s is a library-wide invariant, not a per-backend convention — close the sign_direct/4 bypass [D:3/B:7/U:7 → Eff:2.33] 🎯 |
| Task 2119 | 🔶 | 🎁 **cartouche_coverage_pushes** · 🔒 Re-run the mutation-adequacy campaign once muex can report survivors [D:5/B:7/U:3 → Eff:1.0] 📋 ⛔ muex 0.8.3 fixes survivor reporting (Oeditus/muex#20) but Oeditus/muex#23 (sandboxes share the project _build, so a mutant can be graded on unmutated code) and Oeditus/muex#24 (mutations keyed by reported line, so StatementDeletion and bare-boolean flips are never applied) are open; a 2026-08-24 campaign was run and discarded. Unblocks when a muex release carries both fixes and the per-defect gate in the first acceptance criterion passes |
| Task 2120 | ✅ | 🎁 **cartouche_rpc_correctness** · Cartouche.RPC.create_access_list/2 — eth_createAccessList [D:3/B:7/U:6 → Eff:2.17] 🎯 |
| Task 2121 | ✅ | 🎁 **cartouche_rpc_correctness** · Complete the Cartouche.Filter lifecycle — uninstall, getFilterLogs, and the block/pending filter kinds [D:4/B:7/U:7 → Eff:1.75] 🚀 |
| Task 2122 | ✅ | 🎁 **cartouche_rpc_correctness** · Cartouche.RPC fee reads — eth_baseFee and eth_blobBaseFee [D:2/B:6/U:5 → Eff:2.75] 🎯 |
| Task 2123 | ✅ | 🎁 **cartouche_rpc_correctness** · Cartouche.RPC node introspection — eth_config (EIP-7910) and eth_capabilities [D:4/B:5/U:4 → Eff:1.12] 📋 |
| Task 2124 | ✅ | 🎁 **cartouche_rpc_correctness** · Cartouche.RPC node-custody methods — eth_accounts, eth_coinbase, eth_fillTransaction, eth_sign, eth_signTransaction, eth_sendTransaction [D:4/B:6/U:4 → Eff:1.25] 📋 |
| Task 2125 | ✅ | 🎁 **cartouche_rpc_correctness** · Cartouche.RPC.fill_transaction/2 cannot deserialize a spec-conforming eth_fillTransaction result [D:5/B:5/U:4 → Eff:0.9] ⚠️ |
| Task 2126 | ✅ | 🎁 **cartouche_rpc_correctness** · Spec-path fill_transaction V1 results drop chainId, so encode is pre-EIP-155 [D:4/B:5/U:4 → Eff:1.12] 📋 |
| Task 2127 | ⬜ | 🎁 **cartouche_rpc_correctness** · base_fee/1 portability — probe the real hosted-provider refusal, then decide standard vs extension [D:3/B:7/U:4 → Eff:1.83] 🚀 |
| Task 2128 | ⬜ | 🎁 **cartouche_rpc_read_surface** · Own eth_getLogs in cartouche — stateless log queries, and delete onchain's copy [D:3/B:8/U:7 → Eff:2.5] 🎯 |
| Task 2129 | ⬜ | 🎁 **cartouche_rpc_read_surface** · Own the transaction and receipt read-back in cartouche — 4 methods, and delete onchain's copies [D:4/B:7/U:6 → Eff:1.62] 🚀 |
| Task 2130 | ⬜ | 🎁 **cartouche_rpc_read_surface** · Own the state reads in cartouche — eth_getStorageAt and eth_getProof (EIP-1186) [D:3/B:6/U:5 → Eff:1.83] 🚀 |
| Task 2131 | ⬜ | 🎁 **cartouche_rpc_read_surface** · Own the node-introspection surface in cartouche — and mark the three methods no tagged spec carries [D:3/B:6/U:6 → Eff:2.0] 🎯 |
| Task 2132 | ⬜ | 🎁 **cartouche_rpc_read_surface** · Own eth_simulateV1 in cartouche — the portable simulation entry point [D:5/B:8/U:6 → Eff:1.4] 📋 |
| Task 2133 | ⬜ | 🎁 **cartouche_correctness_010** · 🔒 EIP-712 conformance: encode_type non-termination, bytesN padding direction, array-of-struct support, int types [D:4/B:9/U:8 → Eff:2.12] 🎯 |
| Task 2134 | ⬜ | 🎁 **cartouche_correctness_010** · 🔒 EIP-191 personal_sign byte length, a recovery helper that applies the prefix, and the 65-byte signature invariant [D:3/B:7/U:6 → Eff:2.17] 🎯 |
| Task 2135 | ⬜ | 🎁 **cartouche_rpc_correctness** · Portability contract for the non-standard read surface: trace_* and debug_traceCall [D:3/B:7/U:7 → Eff:2.33] 🎯 |
| Task 2136 | ⬜ | 🎁 **cartouche_rpc_read_surface** · Multi-endpoint live-test seam so node-portability rule 4 can actually be executed [D:3/B:8/U:8 → Eff:2.67] 🎯 |
| Task 2137 | ⬜ | 🎁 **cartouche_rpc_read_surface** · Move the transport hardening into cartouche — retry, telemetry, node-refusal classification, batch [D:5/B:9/U:9 → Eff:1.8] 🚀 |
<!-- TASKS:END -->

### Phase 2001: Spec corrections (immediate onchain wins)

<!-- TASKS:BEGIN phase=2001 -->
> 3 tasks. See [CHANGELOG.md](CHANGELOG.md#phase-2001-cartouche-spec-corrections-immediate-onchain-wins).
<!-- TASKS:END -->

### Phase 2002: Cartouche.RPC.send_rpc/3 error-shape spec

<!-- TASKS:BEGIN phase=2002 -->
> 1 task. See [CHANGELOG.md](CHANGELOG.md#phase-2002-cartouche-cartouche-rpc-send-rpc-3-error-shape-spec).
<!-- TASKS:END -->

### Phase 2003: Cartouche.Trace + Cartouche.TraceCall deserialize specs

<!-- TASKS:BEGIN phase=2003 -->
> 1 task. See [CHANGELOG.md](CHANGELOG.md#phase-2003-cartouche-cartouche-trace-cartouche-tracecall-deserialize-specs).
<!-- TASKS:END -->

### Phase 2004: Cartouche.Typed internal-function specs

<!-- TASKS:BEGIN phase=2004 -->
| Task | Status | Notes |
|------|--------|-------|
| Task 2019+2020 `[CSR]` | ✅ | 🎁 **cartouche_phase4_typed** · Phase 4 Typed internal-function specs — rewrite + visibility judgment [D:3/B:2/U:3 → Eff:0.83?] ⚠️ |
| Task 2098 `[CSR]` | ✅ | 🎁 **cartouche_phase4_typed** · Phase 4 follow-up — tighten Cartouche.Typed.encode_value_map/3 impl so dialyzer infers binary(), restore stricter @spec [D:2/B:2/U:2 → Eff:1.0?] 📋 |
| Task 2045 `[CSR]` | ✅ | 🎁 **cartouche_coverage_pushes** · Cartouche.Typed coverage push — exercise encode_value_map/3 and find_type/2 with representative inputs [D:2/B:2/U:3 → Eff:1.25?] 📋 |
<!-- TASKS:END -->

### Phase 2005: VM / Erc20.Call none() cascade investigation

<!-- TASKS:BEGIN phase=2005 -->
> 1 task. See [CHANGELOG.md](CHANGELOG.md#phase-2005-cartouche-vm-erc20-call-none-cascade-investigation).
<!-- TASKS:END -->

### Phase 2006: Cartouche.VM.Context.init_from/2 spec

<!-- TASKS:BEGIN phase=2006 -->
> 2 tasks. See [CHANGELOG.md](CHANGELOG.md#phase-2006-cartouche-cartouche-vm-context-init-from-2-spec).
<!-- TASKS:END -->

### Phase 2007: Dependency freshness

<!-- TASKS:BEGIN phase=2007 -->
> 7 tasks. See [CHANGELOG.md](CHANGELOG.md#phase-2007-cartouche-dependency-freshness).
<!-- TASKS:END -->

### Phase 2008: Cartouche.Transaction.V2.encode/1 duplication

<!-- TASKS:BEGIN phase=2008 -->
> 2 tasks. See [CHANGELOG.md](CHANGELOG.md#phase-2008-cartouche-cartouche-transaction-v2-encode-1-duplication).
<!-- TASKS:END -->

### Phase 2009: New transaction types + raw decode

<!-- TASKS:BEGIN phase=2009 -->
> 4 tasks. See [CHANGELOG.md](CHANGELOG.md#phase-2009-cartouche-new-transaction-types-raw-decode).
<!-- TASKS:END -->

### Phase 2010: Upstream PR candidates (to hayesgm/signet)

<!-- TASKS:BEGIN phase=2010 -->
| Task | Status | Notes |
|------|--------|-------|
| Task 2034 | ⛔ | 🎁 **cartouche_phase10_upstream** · ABI.decode/2 specced no_return() in poanetwork/ex_abi [D:3/B:5/U:5 → Eff:1.67?] 🚀 |
<!-- TASKS:END -->

### Phase 2011: hieroglyph 1.0.0 → 1.4.0 adoption advisory

<!-- TASKS:BEGIN phase=2011 -->
> 3 tasks. See [CHANGELOG.md](CHANGELOG.md#phase-2011-cartouche-hieroglyph-1-0-0-1-4-0-adoption-advisory).
<!-- TASKS:END -->

### Phase 2012: Agent-economy descripex adoption

<!-- TASKS:BEGIN phase=2012 -->
> 13 tasks. See [CHANGELOG.md](CHANGELOG.md#phase-2012-cartouche-agent-economy-descripex-adoption).
<!-- TASKS:END -->

---

## onchain

### Phase 3007: DEX Infrastructure

<!-- TASKS:BEGIN phase=3007 -->
| Task | Status | Notes |
|------|--------|-------|
| Task 3028 `[P]` | ✅ | 🎁 **onchain_dex** · *Onchain.DEX.Router* · DEX swap routing (optimal path across pools) [D:7/B:8/U:7 → Eff:1.07?] 📋 |
| Task 3029 `[P]` | ✅ | 🎁 **onchain_dex** · *Onchain.MEV* · MEV protection (private transaction submission) [D:6/B:8/U:7 → Eff:1.25?] 📋 |
| Task 3080 | ✅ | 🎁 **onchain_dex** · *Onchain.MEV* · Audit-surfaced: Onchain.MEV accepts block tags where a concrete block is required [D:3/B:4/U:4 → Eff:1.33?] 📋 |
<!-- TASKS:END -->

### Phase 3009: Account Abstraction (ERC-4337)

<!-- TASKS:BEGIN phase=3009 -->
| Task | Status | Notes |
|------|--------|-------|
| Task 3069 `[P]` | ✅ | 🎁 **onchain_account_abstraction** · *Onchain.AA* · ERC-4337 UserOperation construction, signing, and bundler RPC [D:7/B:8/U:7 → Eff:1.07?] 📋 |
| Task 3079 | ✅ | 🎁 **onchain_account_abstraction** · *Onchain.AA* · Audit-surfaced: ERC-4337 to_rpc_params validation can diverge from user_op_hash [D:4/B:5/U:5 → Eff:1.25?] 📋 |
<!-- TASKS:END -->

### Phase 3010: RPC Composition Layer

<!-- TASKS:BEGIN phase=3010 -->
| Task | Status | Notes |
|------|--------|-------|
| Task 3051 | ✅ | 🎁 **onchain_rpc_composition** · *Onchain.RPC* · Onchain.RPC.batch/2 — JSON-RPC 2.0 array-batched requests [D:4/B:6/U:5 → Eff:1.38?] 📋 |
| Task 3052 | ✅ | 🎁 **onchain_rpc_composition** · *Onchain.RPC* · Telemetry events around Onchain.RPC request path [D:3/B:5/U:5 → Eff:1.67?] 🚀 |
| Task 3054 | ✅ | 🎁 **onchain_rpc_composition** · *Onchain.RPC* · Opt-in retry/backoff wrapper over Signet.RPC.send_rpc/3 [D:4/B:5/U:4 → Eff:1.12?] 📋 |
| Task 3081 | ✅ | 🎁 **onchain_rpc_composition** · *Onchain.RPC* · Audit-surfaced: RPC batch + block decode crash on malformed node responses [D:2/B:3/U:4 → Eff:1.75?] 🚀 |
| Task 3082 | ✅ | 🎁 **onchain_rpc_composition** · Add eth_estimateGas RPC helper + auto-estimate gas in send_transaction [D:3/B:5/U:6 → Eff:1.83?] 🚀 |
<!-- TASKS:END -->

### Phase 3012: Code Health

<!-- TASKS:BEGIN phase=3012 -->
| Task | Status | Notes |
|------|--------|-------|
| Task 3057 | ✅ | 🎁 **onchain_rpc_shapes** · *Onchain.RPC* · Unify get_block_* / get_transaction_* RPC return shapes [D:4/B:6/U:6 → Eff:1.5?] 🚀 |
| Task 3063 | ✅ | 🎁 **onchain_rpc_codegen** · *Onchain.RPC* · defrpc macro — codegen named JSON-RPC wrappers from declarative specs [D:4/B:6/U:5 → Eff:1.38?] 📋 |
| Task 3064 | ✅ | 🎁 **onchain_rpc_codegen** · *Onchain.RPC.Specs* · Vendor openrpc.json + emit Onchain.RPC.Specs lookup feeding defrpc [D:4/B:6/U:5 → Eff:1.38?] 📋 |
| Task 3066 | ✅ | 🎁 **onchain_rpc_codegen** · *Mix.Task (dev-only)* · Tree-sitter scrape of Erigon Go source for trace_* / ots_* method enumeration [D:5/B:4/U:3 → Eff:0.7?] ⚠️ |
| Task 3041 `[P]` | ✅ | 🎁 **onchain_ens** · *Onchain.ENS* · ENS enhancements: CCIP-Read, ENSIP-10 wildcard, UTS-46/ENSIP-15 normalization, multi-coin [D:6/B:6/U:5 → Eff:0.92?] ⚠️ |
| Task 3065 `[P]` | ✅ | 🎁 **onchain_differential_testing** · *test/onchain/differential/* · Differential test harness: Onchain.RPC vs reference impl (signet first) [D:6/B:5/U:3 → Eff:0.67?] ⚠️ |
| Task 3070 `[P]` | ✅ | 🎁 **onchain_subscription_hardening** · *Onchain.Subscription* · Harden Onchain.Subscription.lookup_or_buffer/3 against unsolicited sub_id keys [D:3/B:4/U:3 → Eff:1.17?] 📋 |
| Task 3074 `[P]` | ✅ | 🎁 **onchain_erc_standards** · *Onchain.ERC7730* · ERC-7730 clear-signing descriptor parser + binding evaluator [D:6/B:7/U:6 → Eff:1.08?] 📋 |
| Task 3075 | ✅ | 🎁 **onchain_rpc_shapes** · Stop dialyzer cold-building the PLT per harness worktree (it OOM'd the host twice) [D:2/B:3/U:5 → Eff:2.0?] 🎯 |
| Task 3076 | ✅ | 🎁 **onchain_rpc_codegen** · *Onchain.RPC* · Audit-surfaced: Task 63 defrpc macro is unused — wrappers still hand-written [D:4/B:5/U:5 → Eff:1.25?] 📋 |
| Task 3077 | ✅ | 🎁 **onchain_erc_standards** · *Onchain.ERC7730.Formatter* · Audit-surfaced: ERC-7730 tokenAmount renders wrong token symbol (clear-signing safety) [D:4/B:7/U:6 → Eff:1.62?] 🚀 |
| Task 3078 | ✅ | 🎁 **onchain_erc_standards** · *Onchain.ERC7730.Binding* · Audit-surfaced: ERC-7730 binding/descriptor hardening (domain match, EIP-712 type, malformed input) [D:5/B:5/U:5 → Eff:1.0?] 📋 |
| Task 3083 | ✅ | 🎁 **onchain_rpc_composition** · *Onchain.RPC* · Migrate HTTP transport off cartouche's removed Finch seams (cartouche 0.5.0) [D:4/B:8/U:8 → Eff:2.0?] 🎯 |
| Task 3084 | ⬜ | 🎁 **onchain_differential_testing** · 🔒 Mutation-grade RPC construction and DEX math invariants [D:6/B:9/U:7 → Eff:1.33] 📋 |
| Task 3085 `[P]` | ✅ | 🎁 **onchain_rpc_composition** · Onchain.RPC block-level reads — receipts, transaction counts, transactions by index, and the block access list [D:4/B:7/U:6 → Eff:1.62] 🚀 |
| Task 3086 `[P]` | ⬜ | 🎁 **onchain_rpc_composition** · Onchain.RPC.get_storage_values — eth_getStorageValues batched multi-account slot reads [D:3/B:6/U:5 → Eff:1.83] 🚀 |
| Task 3087 | ⬜ | 🎁 **onchain_differential_testing** · 🔒 Mutation-adequacy campaign over the signing, key and address surface [D:5/B:8/U:3 → Eff:1.1] 📋 |
| Task 3088 | ✅ | 🎁 **onchain_abi_decode_hardening** · 🔒 Expose hieroglyph's strict decode mode through the Onchain.ABI, Contract and Log decode surface [D:4/B:7/U:6 → Eff:1.62] 🚀 |
| Task 3089 | ⬜ | 🎁 **onchain_signer_backend_contract** · 🔒 Route Onchain.Signer.sign_transaction through cartouche's {backend, config} carrier instead of the legacy MFA [D:3/B:7/U:6 → Eff:2.17] 🎯 |
| Task 3090 | ⬜ | 🎁 **onchain_subscription_hardening** · HTTP log/block/pending polling over Cartouche.Filter, so subscribers work on the RPC URL this library defaults to [D:5/B:6/U:5 → Eff:1.1] 📋 |
| Task 3091 | ✅ | 🎁 **onchain_node_portability** · Normalize node-capability refusals into typed errors instead of passing the raw JSON-RPC code through [D:3/B:7/U:7 → Eff:2.33] 🎯 |
| Task 3092 | ⬜ | 🎁 **onchain_node_portability** · Onchain.RPC node introspection — eth_config and eth_capabilities so a consumer can discover what their node actually serves [D:4/B:7/U:6 → Eff:1.62] 🚀 |
| Task 3093 | ⬜ | 🎁 **onchain_rpc_composition** · Onchain.RPC.create_access_list — compute the EIP-2930 access list that Signer.build_transaction already accepts but cannot produce [D:4/B:6/U:5 → Eff:1.38] 📋 |
<!-- TASKS:END -->

---

## onchain_aave

### Phase 4001: Aave Core (Read)

<!-- TASKS:BEGIN phase=4001 -->
> 8 tasks. See [CHANGELOG.md](CHANGELOG.md#phase-4001-onchain-aave-aave-core-read).
<!-- TASKS:END -->

### Phase 4002: Aave Actions (Write)

<!-- TASKS:BEGIN phase=4002 -->
> 3 tasks. See [CHANGELOG.md](CHANGELOG.md#phase-4002-onchain-aave-aave-actions-write).
<!-- TASKS:END -->

### Phase 4003: Math Validation

<!-- TASKS:BEGIN phase=4003 -->
> 6 tasks. See [CHANGELOG.md](CHANGELOG.md#phase-4003-onchain-aave-math-validation).
<!-- TASKS:END -->

### Phase 4004: Cleanup Backlog

<!-- TASKS:BEGIN phase=4004 -->
> 4 tasks. See [CHANGELOG.md](CHANGELOG.md#phase-4004-onchain-aave-cleanup-backlog).
<!-- TASKS:END -->

### Phase 4005: Aave V4 Support

<!-- TASKS:BEGIN phase=4005 -->
| Task | Status | Notes |
|------|--------|-------|
| Task 4044 | ✅ | 🎁 **onchain_aave_v4_support** · *V4_SCOPING.md* · Research V4 Hub-and-Spoke contract surface and scope the V4 support phase [D:3/B:7/U:8 → Eff:2.5?] 🎯 |
| Task 4045 | ✅ | 🎁 **onchain_aave_v4_support** · *Onchain.Aave.Contracts* · Extend Onchain.Aave.Contracts with V4 address keys [D:4/B:7/U:8 → Eff:1.88?] 🚀 |
| Task 4046 `[P]` | ✅ | 🎁 **onchain_aave_v4_support** · *V4_SCOPING.md* · Select V4 read surface by diffing IHub/ISpoke/IAaveOracle/ITokenizationSpoke against V3 IPool [D:3/B:6/U:7 → Eff:2.17?] 🎯 |
| Task 4047 `[P]` | ✅ | 🎁 **onchain_aave_v4_support** · *Onchain.Aave.V4.Hub* · Implement Onchain.Aave.V4.Hub read wrapper [D:4/B:6/U:5 → Eff:1.38?] 📋 |
| Task 4048 `[P]` | ✅ | 🎁 **onchain_aave_v4_support** · *Onchain.Aave.V4.Spoke* · Implement Onchain.Aave.V4.Spoke reads + V4 types [D:5/B:7/U:7 → Eff:1.4?] 📋 |
| Task 4049 `[P]` | ✅ | 🎁 **onchain_aave_v4_support** · *Onchain.Aave.V4.Oracle* · Implement Onchain.Aave.V4.Oracle wrapper (Spoke-scoped) [D:3/B:5/U:5 → Eff:1.67?] 🚀 |
| Task 4050 `[P]` | ✅ | 🎁 **onchain_aave_v4_support** · *Onchain.Aave.V4.TokenizationSpoke* · Implement Onchain.Aave.V4.TokenizationSpoke reads (ERC-4626 share accounting) [D:3/B:5/U:5 → Eff:1.67?] 🚀 |
| Task 4051 | ✅ | 🎁 **onchain_aave_v4_support** · *Onchain.Aave.V4.PositionManager* · Implement Onchain.Aave.V4.PositionManager ergonomic write wrappers (supply/borrow/repay analogs) [D:5/B:8/U:7 → Eff:1.5?] 🚀 |
| Task 4052 | ✅ | 🎁 **onchain_aave_v4_support** · 🚀 **onchain_aave_v0_5** · *test/onchain/aave/v4/* · 🔒 Prove V4 reads and PositionManager writes against deployed mainnet state [D:6/B:9/U:9 → Eff:1.5] 🚀 |
| Task 4057 | ✅ | 🎁 **onchain_aave_v4_support** · *Onchain.Aave.V4.Hub* · Wrap remaining IHub preview converters and Hub bound constants [D:3/B:4/U:5 → Eff:1.5] 🚀 |
| Task 4066 | ⬜ | 🎁 **onchain_aave_v4_support** · *Onchain.Aave.V4.TokenizationSpoke* · Execute the V4 Tokenization Spoke: ERC-4626 writes and the share token's ERC-20 surface [D:5/B:8/U:8 → Eff:1.6] 🚀 |
| Task 4067 | ⬜ | 🎁 **onchain_aave_v4_support** · *Onchain.Aave.V4.PositionManager* · Wrap V4 position configuration and position-manager authorization, and close the Taker fork-evidence gap [D:4/B:8/U:8 → Eff:2.0] 🎯 |
| Task 4069 | ⬜ | 🎁 **onchain_aave_v4_support** · *Onchain.Aave.Contracts* · Re-sync the V4 address registry with the deployed surface and stop hardcoding three Hubs [D:4/B:9/U:9 → Eff:2.25] 🎯 |
| Task 4070 | ⬜ | 🎁 **onchain_aave_v4_support** · *Onchain.Aave.Contracts* · Register the ether.fi Cash V4 whitelabel instance on Optimism [D:4/B:8/U:8 → Eff:2.0] 🎯 |
<!-- TASKS:END -->

### Phase 4006: V3 Write Surface Gaps

<!-- TASKS:BEGIN phase=4006 -->
| Task | Status | Notes |
|------|--------|-------|
| Task 4053 | ✅ | 🎁 **onchain_aave_v3_write_gaps** · *Onchain.Aave.DebtToken* · Onchain.Aave.DebtToken — wrap approveDelegation + borrowAllowance on variable/stable debt tokens [D:3/B:6/U:6 → Eff:2.0?] 🎯 |
| Task 4054 | ✅ | 🎁 **onchain_aave_v3_write_gaps** · *(cross-cutting research)* · Mine defi-skills:intent-to-transaction action surface for onchain_aave coverage gaps [D:3/B:8/U:7 → Eff:2.5?] 🎯 |
| Task 4058 | ⬜ | 🎁 **onchain_aave_v3_write_gaps** · 🚀 **onchain_aave_v0_5** · *Onchain.Aave.Pool* · Onchain.Aave.Pool — eMode: setUserEMode, getUserEMode, category config, and enumeration via getEModes [D:5/B:8/U:7 → Eff:1.5] 🚀 |
| Task 4059 | ⬜ | 🎁 **onchain_aave_v3_write_gaps** · 🚀 **onchain_aave_v0_5** · *Onchain.Aave.Pool* · Retire stable-rate APIs and resolve variable debt tokens through the dedicated Pool getter [D:4/B:8/U:7 → Eff:1.88] 🚀 |
| Task 4060 | ⬜ | 🎁 **onchain_aave_v3_write_gaps** · 🚀 **onchain_aave_v0_5** · *Onchain.Aave.Pool* · Onchain.Aave.Pool — setUserUseReserveAsCollateral and repayWithATokens [D:4/B:7/U:7 → Eff:1.75] 🚀 |
| Task 4061 | ⬜ | 🎁 **onchain_aave_v3_write_gaps** · 🚀 **onchain_aave_v0_5** · *Onchain.Aave.Pool* · Expose typed direct reserve data and normalized index reads [D:4/B:5/U:5 → Eff:1.25] 📋 |
| Task 4062 | ⬜ | 🎁 **onchain_aave_v3_write_gaps** · Make the integration gate settle: bound math_revm runtime so --include integration terminates [D:4/B:7/U:8 → Eff:1.88] 🚀 |
<!-- TASKS:END -->

### Phase 4007: Read-Path Multicall Adoption

<!-- TASKS:BEGIN phase=4007 -->
> 1 task. See [CHANGELOG.md](CHANGELOG.md#phase-4007-onchain-aave-read-path-multicall-adoption).
<!-- TASKS:END -->

### Phase 4008: Event & Revert Decoding

<!-- TASKS:BEGIN phase=4008 -->
| Task | Status | Notes |
|------|--------|-------|
| Task 4063 | ⬜ | 🎁 **onchain_aave_event_error_decoding** · *Onchain.Aave.Events* · Decode deployed Aave V3 Pool events from logs with topic-filter fetch [D:5/B:8/U:7 → Eff:1.5] 🚀 |
| Task 4064 | ⬜ | 🎁 **onchain_aave_event_error_decoding** · Surface decoded revert reasons on Aave write and call failures [D:4/B:7/U:7 → Eff:1.75] 🚀 |
| Task 4065 | 🔶 | 🎁 **onchain_aave_event_error_decoding** · Adopt strict ABI decoding across Aave response decode paths [D:3/B:6/U:5 → Eff:1.83] 🚀 ⛔ onchain task 88 must land first: Onchain.ABI.decode_response/2 and Onchain.Contract.call accept no decode options today, so strict mode is unreachable from this repo |
| Task 4068 | ⬜ | 🎁 **onchain_aave_event_error_decoding** · *Onchain.Aave.Events* · Decode V4 Hub, Spoke and Tokenization Spoke events from logs [D:5/B:8/U:7 → Eff:1.5] 🚀 |
<!-- TASKS:END -->

---

## onchain_aerodrome

### Phase 5001: Foundations & Layer Gate

<!-- TASKS:BEGIN phase=5001 -->
| Task | Status | Notes |
|------|--------|-------|
| Task 5001 | ⬜ | 🎁 **onchain_aerodrome_foundations** · 🚀 **onchain_aerodrome_v0_1** · *Onchain.Aerodrome* · Close the reach layer-gate holes so analytics-never-touches-the-network is enforced, not documented [D:5/B:9/U:8 → Eff:1.7] 🚀 |
| Task 5002 `[P]` | ⬜ | 🎁 **onchain_aerodrome_foundations** · 🚀 **onchain_aerodrome_v0_1** · *Onchain.Aerodrome.Epoch* · Onchain.Aerodrome.Epoch — weekly ve(3,3) epoch arithmetic [D:3/B:7/U:9 → Eff:2.67] 🎯 |
| Task 5003 | ⬜ | 🎁 **onchain_aerodrome_foundations** · 🚀 **onchain_aerodrome_v0_1** · *Onchain.Aerodrome.Bindings.Abi* · Decode strategy and Bindings.Abi signature plumbing from priv/abis [D:5/B:8/U:8 → Eff:1.6] 🚀 |
| Task 5004 | ⬜ | 🎁 **onchain_aerodrome_foundations** · 🚀 **onchain_aerodrome_v0_1** · *Mix.Tasks.Aerodrome.CaptureFixtures* · Golden-fixture capture harness: pinned-block eth_call fixtures and an offline loader [D:4/B:7/U:8 → Eff:1.88] 🚀 |
| Task 5005 `[P]` | ⬜ | 🎁 **onchain_aerodrome_foundations** · 🚀 **onchain_aerodrome_v0_1** · *Onchain.Aerodrome.RPCCase* · Onchain.Aerodrome.RPCCase — the first multi-endpoint portability test seam in the family [D:4/B:7/U:8 → Eff:1.88] 🚀 |
<!-- TASKS:END -->

### Phase 5002: Types

<!-- TASKS:BEGIN phase=5002 -->
| Task | Status | Notes |
|------|--------|-------|
| Task 5006 `[P]` | ⬜ | 🎁 **onchain_aerodrome_types** · 🚀 **onchain_aerodrome_v0_1** · *Onchain.Aerodrome.Types.Lp* · Types.Lp, .Position, .Swap and .Token — the pool and token structs, with ABI drift tests [D:5/B:8/U:8 → Eff:1.6] 🚀 |
| Task 5007 `[P]` | ⬜ | 🎁 **onchain_aerodrome_types** · 🚀 **onchain_aerodrome_v0_1** · *Onchain.Aerodrome.Types.VeNFT* · Types.VeNFT, .Vote, .Relay, .LpEpoch and .Reward — the veAERO structs, with ABI drift tests [D:5/B:8/U:8 → Eff:1.6] 🚀 |
<!-- TASKS:END -->

### Phase 5003: Bindings

<!-- TASKS:BEGIN phase=5003 -->
| Task | Status | Notes |
|------|--------|-------|
| Task 5008 | ⬜ | 🎁 **onchain_aerodrome_bindings** · 🚀 **onchain_aerodrome_v0_1** · *Onchain.Aerodrome.Bindings.LpSugar* · Bindings.LpSugar — the full read surface and the count()-driven pagination driver [D:6/B:9/U:9 → Eff:1.5] 🚀 |
| Task 5009 `[P]` | ⬜ | 🎁 **onchain_aerodrome_bindings** · 🚀 **onchain_aerodrome_v0_1** · *Onchain.Aerodrome.Bindings.RewardsSugar* · Bindings.RewardsSugar and Bindings.VeSugar [D:4/B:7/U:7 → Eff:1.75] 🚀 |
| Task 5010 `[P]` | ⬜ | 🎁 **onchain_aerodrome_bindings** · 🚀 **onchain_aerodrome_v0_1** · *Onchain.Aerodrome.Bindings.RelaySugar* · Bindings.RelaySugar and Bindings.TokenSugar [D:3/B:6/U:6 → Eff:2.0] 🎯 |
| Task 5011 `[P]` | ⬜ | 🎁 **onchain_aerodrome_bindings** · 🚀 **onchain_aerodrome_v0_1** · *Onchain.Aerodrome.Bindings.Factories* · Bindings.Factories — PoolFactory, CLFactory and SlipstreamHelper [D:4/B:6/U:6 → Eff:1.5] 🚀 |
| Task 5012 `[P]` | ⬜ | 🎁 **onchain_aerodrome_bindings** · 🚀 **onchain_aerodrome_v0_1** · *Onchain.Aerodrome.Bindings.Voter* · Bindings.Voter — the read surface (epochs, weights, gauge and pool registry) [D:3/B:6/U:6 → Eff:2.0] 🎯 |
<!-- TASKS:END -->

### Phase 5004: Pure Math

<!-- TASKS:BEGIN phase=5004 -->
| Task | Status | Notes |
|------|--------|-------|
| Task 5013 | ⬜ | 🎁 **onchain_aerodrome_math** · 🚀 **onchain_aerodrome_v0_1** · *Onchain.Aerodrome.Math.Tick* · Math.Tick — port Slipstream TickMath and grade it over a swept int24 domain [D:6/B:10/U:8 → Eff:1.5] 🚀 |
| Task 5014 `[P]` | ⬜ | 🎁 **onchain_aerodrome_math** · 🚀 **onchain_aerodrome_v0_1** · *Onchain.Aerodrome.Math.Liquidity* · Math.Liquidity — amounts and liquidity conversion plus signed and unsigned deltas, differentially graded [D:5/B:8/U:7 → Eff:1.5] 🚀 |
| Task 5015 `[P]` | ⬜ | 🎁 **onchain_aerodrome_math** · 🚀 **onchain_aerodrome_v0_1** · *Onchain.Aerodrome.Math.Stable* · Math.Stable — the Solidly stable invariant and v2 constant-product quoting [D:5/B:7/U:7 → Eff:1.4] 📋 |
| Task 5016 | ⬜ | 🎁 **onchain_aerodrome_math** · 🚀 **onchain_aerodrome_v0_1** · *Onchain.Aerodrome.Math.Price* · Math.Price — decimals-aware price conversion from sqrtX96, reserves and the stable invariant [D:4/B:8/U:8 → Eff:2.0] 🎯 |
<!-- TASKS:END -->

### Phase 5005: Price Layer

<!-- TASKS:BEGIN phase=5005 -->
| Task | Status | Notes |
|------|--------|-------|
| Task 5017 | ⬜ | 🎁 **onchain_aerodrome_price** · 🚀 **onchain_aerodrome_v0_1** · *Onchain.Aerodrome.Analytics.Price* · Types.Price and .PriceMap plus Analytics.Price — pure spot pricing and numeraire route resolution [D:5/B:8/U:8 → Eff:1.6] 🚀 |
| Task 5018 | ⬜ | 🎁 **onchain_aerodrome_price** · 🚀 **onchain_aerodrome_v0_1** · *Onchain.Aerodrome.Sugar.Prices* · Bindings.Chainlink and Sugar.Prices — anchor feeds with a staleness policy, materialising a PriceMap [D:5/B:8/U:8 → Eff:1.6] 🚀 |
<!-- TASKS:END -->

### Phase 5006: Analytics

<!-- TASKS:BEGIN phase=5006 -->
| Task | Status | Notes |
|------|--------|-------|
| Task 5019 `[P]` | ⬜ | 🎁 **onchain_aerodrome_analytics** · 🚀 **onchain_aerodrome_v0_1** · *Onchain.Aerodrome.Analytics.Pool* · Analytics.Pool — pool typing, TVL, staked share and verified fee-unit semantics [D:4/B:7/U:8 → Eff:1.88] 🚀 |
| Task 5020 `[P]` | ⬜ | 🎁 **onchain_aerodrome_analytics** · 🚀 **onchain_aerodrome_v0_1** · *Onchain.Aerodrome.Analytics.Position* · Analytics.Position — principal, range state and valuation, cross-graded against Sugar's own amounts [D:5/B:8/U:8 → Eff:1.6] 🚀 |
| Task 5021 | ⬜ | 🎁 **onchain_aerodrome_analytics** · 🚀 **onchain_aerodrome_v0_1** · *Onchain.Aerodrome.Analytics.APR* · Analytics.APR — separate fee and emission rates, each carrying its denominator as data [D:5/B:8/U:9 → Eff:1.7] 🚀 |
| Task 5022 | ⬜ | 🎁 **onchain_aerodrome_analytics** · 🚀 **onchain_aerodrome_v0_1** · *Onchain.Aerodrome.Analytics.APR* · APR invariant enforcement, the 7.53 percent golden, and the tiered coverage gate [D:6/B:10/U:8 → Eff:1.5] 🚀 |
<!-- TASKS:END -->

### Phase 5007: Read API

<!-- TASKS:BEGIN phase=5007 -->
| Task | Status | Notes |
|------|--------|-------|
| Task 5023 `[P]` | ⬜ | 🎁 **onchain_aerodrome_read_api** · 🚀 **onchain_aerodrome_v0_1** · *Onchain.Aerodrome.Sugar.Pools* · Sugar.Pools and Sugar.Tokens — the ergonomic pool and token read API [D:4/B:8/U:8 → Eff:2.0] 🎯 |
| Task 5024 `[P]` | ⬜ | 🎁 **onchain_aerodrome_read_api** · 🚀 **onchain_aerodrome_v0_1** · *Onchain.Aerodrome.Sugar.Positions* · Sugar.Positions, .VeNfts, .Rewards and .Relays — the account-scoped read API [D:4/B:7/U:7 → Eff:1.75] 🚀 |
<!-- TASKS:END -->

### Phase 5008: Evidence & Release

<!-- TASKS:BEGIN phase=5008 -->
| Task | Status | Notes |
|------|--------|-------|
| Task 5032 `[P]` | ⬜ | 🎁 **onchain_aerodrome_evidence_release** · 🚀 **onchain_aerodrome_v0_1** · *Onchain.Aerodrome.AbiDrift* · Runnable ABI-drift detector: re-fetch every priv/abis entry and diff selector sets [D:4/B:7/U:7 → Eff:1.75] 🚀 |
| Task 5033 | ⬜ | 🎁 **onchain_aerodrome_evidence_release** · 🚀 **onchain_aerodrome_v0_1** · *Onchain.Aerodrome* · Live integration proof of the full read, analytics and price surface across two endpoints [D:4/B:8/U:9 → Eff:2.12] 🎯 |
| Task 5034 | ⬜ | 🎁 **onchain_aerodrome_evidence_release** · 🚀 **onchain_aerodrome_v0_1** · *OnchainAerodrome* · 📝 Cut 0.1.0: CHANGELOG, README status, SECURITY scope, descripex roster and a hex build dry run [D:3/B:6/U:7 → Eff:2.17] 🎯 |
<!-- TASKS:END -->

### Phase 5009: Write Surface

<!-- TASKS:BEGIN phase=5009 -->
| Task | Status | Notes |
|------|--------|-------|
| Task 5025 | ⬜ | 🎁 **onchain_aerodrome_write** · 🚀 **onchain_aerodrome_v0_2** · *Onchain.Aerodrome.Contracts* · 🔒 Capture Router, Gauge and NFPM ABIs from Sourcify and extend the registry with two-source-verified addresses [D:5/B:9/U:8 → Eff:1.7] 🚀 |
| Task 5026 `[P]` | ⬜ | 🎁 **onchain_aerodrome_write** · 🚀 **onchain_aerodrome_v0_2** · *Onchain.Aerodrome.CalldataFixture* · 🔒 Golden-calldata evidence harness: an independent cast oracle plus eth_call impersonation, proven on Voter [D:5/B:8/U:8 → Eff:1.6] 🚀 |
| Task 5027 `[P]` | ⬜ | 🎁 **onchain_aerodrome_write** · 🚀 **onchain_aerodrome_v0_2** · *Onchain.Aerodrome.Write.Voter* · 🔒 Write.Voter — vote, reset, poke, claims, managed deposits and distribute [D:5/B:7/U:6 → Eff:1.3] 📋 |
| Task 5028 | ⬜ | 🎁 **onchain_aerodrome_write** · 🚀 **onchain_aerodrome_v0_2** · *Onchain.Aerodrome.Write.Router* · 🔒 Write.Router — swap and liquidity calldata builders with Signer opt-in [D:6/B:8/U:7 → Eff:1.25] 📋 |
| Task 5029 `[P]` | ⬜ | 🎁 **onchain_aerodrome_write** · 🚀 **onchain_aerodrome_v0_2** · *Onchain.Aerodrome.Write.Gauge* · 🔒 Write.Gauge — stake, unstake and claim calldata builders [D:4/B:7/U:7 → Eff:1.75] 🚀 |
| Task 5030 `[P]` | ⬜ | 🎁 **onchain_aerodrome_write** · 🚀 **onchain_aerodrome_v0_2** · *Onchain.Aerodrome.Write.NFPM* · 🔒 Write.NFPM — Slipstream concentrated-liquidity position lifecycle [D:6/B:8/U:7 → Eff:1.25] 📋 |
| Task 5031 | ⬜ | 🎁 **onchain_aerodrome_write** · 🚀 **onchain_aerodrome_v0_2** · *Onchain.Aerodrome.CalldataFixture* · 🔒 Mutation-survivor audit: prove the golden-calldata comparators actually discriminate [D:5/B:9/U:6 → Eff:1.5] 🚀 |
| Task 5035 | ⬜ | 🎁 **onchain_aerodrome_write** · 🚀 **onchain_aerodrome_v0_2** · *OnchainAerodrome* · 📝 Cut 0.2.0: live write-surface evidence capstone, CHANGELOG, SECURITY scope and descripex roster for Write.* [D:4/B:7/U:7 → Eff:1.75] 🚀 |
<!-- TASKS:END -->

---

## onchain_evm

### Phase 6001: Foundation

<!-- TASKS:BEGIN phase=6001 -->
> 5 tasks. See [CHANGELOG.md](CHANGELOG.md#phase-6001-onchain-evm-foundation).
<!-- TASKS:END -->

### Phase 6002: Quality & Reliability Improvements

<!-- TASKS:BEGIN phase=6002 -->
> 23 tasks. See [CHANGELOG.md](CHANGELOG.md#phase-6002-onchain-evm-quality-reliability-improvements).
<!-- TASKS:END -->

### Phase 6003: Standalone & Release

<!-- TASKS:BEGIN phase=6003 -->
> 14 tasks. See [CHANGELOG.md](CHANGELOG.md#phase-6003-onchain-evm-standalone-release).
<!-- TASKS:END -->

---

## onchain_js

### Phase 7001: Foundation

<!-- TASKS:BEGIN phase=7001 -->
| Task | Status | Notes |
|------|--------|-------|
| Task 7001 | 🔄 | 🎁 **onchain_js_foundation** · 🚀 **onchain_js_v0_3** · QuickBEAM foundation [D:3/B:7/U:8 → Eff:2.5] 🎯 |
<!-- TASKS:END -->

### Phase 7002: Ethereum JS Tools

<!-- TASKS:BEGIN phase=7002 -->
| Task | Status | Notes |
|------|--------|-------|
| Task 7002 | ⬜ | 🎁 **onchain_js_eth_tools** · 🚀 **onchain_js_v0_3** · *OnchainJs.Solc* · solc-js compilation (.sol → ABI + bytecode) [D:4/B:9/U:8 → Eff:2.12] 🎯 |
| Task 7003 | ⬜ | 🎁 **onchain_js_eth_tools** · 🚀 **onchain_js_v0_4** · *OnchainJs.Uniswap* · Uniswap v3 SDK routing (optimal swap paths, price impact) [D:5/B:8/U:7 → Eff:1.5] 🚀 |
| Task 7004 | ⬜ | 🎁 **onchain_js_eth_tools** · 🚀 **onchain_js_v0_4** · DeFiSaver recipe builder (@defisaver/sdk) [D:5/B:8/U:7 → Eff:1.5] 🚀 |
| Task 7005 | ⬜ | 🎁 **onchain_js_eth_tools** · 🚀 **onchain_js_v0_4** · 1inch Fusion SDK (DEX aggregation) [D:5/B:7/U:6 → Eff:1.3] 📋 |
<!-- TASKS:END -->

### Phase 7003: Cross-Validation & Utilities

<!-- TASKS:BEGIN phase=7003 -->
| Task | Status | Notes |
|------|--------|-------|
| Task 7006 | ⬜ | 🎁 **onchain_js_cross_validation** · 🚀 **onchain_js_v0_4** · Aave math-utils cross-validation [D:3/B:5/U:4 → Eff:1.5] 🚀 |
| Task 7007 | ⬜ | 🎁 **onchain_js_cross_validation** · 🚀 **onchain_js_v0_4** · *OnchainJs.Merkle* · Merkle proof construction (airdrops, whitelists, storage proofs) [D:3/B:6/U:5 → Eff:1.83] 🚀 |
<!-- TASKS:END -->

---

## onchain_tempo

### Phase 8001: Extraction from MPP

<!-- TASKS:BEGIN phase=8001 -->
> 1 task. See [CHANGELOG.md](CHANGELOG.md#phase-8001-onchain-tempo-extraction-from-mpp).
<!-- TASKS:END -->

### Phase 8002: Hex Release & Integration Coverage

<!-- TASKS:BEGIN phase=8002 -->
> 6 tasks. See [CHANGELOG.md](CHANGELOG.md#phase-8002-onchain-tempo-hex-release-integration-coverage).
<!-- TASKS:END -->

### Phase 8003: Future Work

<!-- TASKS:BEGIN phase=8003 -->
| Task | Status | Notes |
|------|--------|-------|
| Task 8006 | ✅ | 🎁 **onchain_tempo_faucet_polish** · Replace Faucet fixed-sleep settle with poll loop [D:3/B:3/U:3 → Eff:1.0?] 📋 |
| Task 8007 | ✅ | 🎁 **onchain_tempo_public_faucet** · Public `Onchain.Tempo.Faucet` helper for `tempo_fundAddress` [D:2/B:5/U:5 → Eff:2.5?] 🎯 |
| Task 8010 | ✅ | 🎁 **onchain_tempo_integration_coverage** · Stop hardcoding Builder @default_gas_limit — estimate gas per-tx (mirror mppx) [D:3/B:4/U:6 → Eff:1.67?] 🚀 |
| Task 8011 | ✅ | 🎁 **onchain_tempo_cartouche_migration** · Update transport stub off the :cartouche,:client seam after onchain's Req migration [D:2/B:5/U:5 → Eff:2.5?] 🎯 |
| Task 8012 | ✅ | 🎁 **onchain_tempo_verification** · 🔒 Mutation-grade 0x76 transaction and signing invariants [D:5/B:9/U:8 → Eff:1.7] 🚀 |
| Task 8013 | ⬜ | 🎁 **onchain_tempo_verification** · 🔒 Verify optional 0x76 key_authorization across encode, sign, and recover [D:5/B:7/U:4 → Eff:1.1] 📋 |
<!-- TASKS:END -->

---
